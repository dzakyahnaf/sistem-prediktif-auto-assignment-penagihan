import copy
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
import io
import json
from pathlib import Path
import shutil
import tempfile
import unittest
from unittest.mock import patch
from uuid import uuid4
import zipfile
from fastapi.testclient import TestClient
from app.main import create_app
from app.seed import DEMO_PASSWORD
from app.historical import content_hash, encode
from app.model_engine import infer, train_release


class ModelTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp=tempfile.TemporaryDirectory();cls.base=Path(cls.temp.name)/'base.db'
        cls.now=datetime(2026,10,28,2,tzinfo=timezone.utc)
        with TestClient(create_app(str(cls.base),lambda:cls.now)) as client:
            h={'Authorization':'Bearer '+client.post('/api/auth/login',json=dict(username='supervisor',password=DEMO_PASSWORD)).json()['access_token']}
            r=client.post('/api/analytics/runs',headers=h,json=dict(request_key='models-fixture-dataset'))
            assert r.status_code==201,r.text;cls.dataset=r.json()
            r=client.post('/api/models/train',headers=h,json=dict(run_id=cls.dataset['id'],request_key='models-fixture-training'))
            assert r.status_code==201,r.text;cls.release=r.json()
            with client.app.state.db.connect() as conn:
                cls.artifact=json.loads(conn.execute('SELECT artifact FROM ml_releases').fetchone()[0])
                cls.samples=[json.loads(r[0]) for r in conn.execute('SELECT payload FROM analytics_samples ORDER BY record_id')]

    @classmethod
    def tearDownClass(cls):cls.temp.cleanup()
    def setUp(self):
        self.path=Path(self.temp.name)/(uuid4().hex+'.db');shutil.copy2(self.base,self.path)
        self.now=datetime(2026,10,28,2,tzinfo=timezone.utc)
        self.app=create_app(str(self.path),lambda:self.now);self.client=TestClient(self.app).__enter__();self.h=self.login('supervisor')
    def tearDown(self):self.client.__exit__(None,None,None)
    def login(self,name):
        r=self.client.post('/api/auth/login',json=dict(username=name,password=DEMO_PASSWORD));self.assertEqual(r.status_code,200,r.text)
        return {'Authorization':'Bearer '+r.json()['access_token']}
    def call(self,method,path,payload=None,status=200):
        r=self.client.request(method,path,headers=self.h,json=payload);self.assertEqual(r.status_code,status,r.text[:500]);return r.json()
    def activate(self,release=True):
        current=self.call('GET','/api/models/serving')
        return self.call('POST','/api/models/serving',dict(release_id=self.release['id'] if release else None,expected_revision=current['revision'],demo_ack=release,
            reason='Pengujian model simulasi terpadu',request_key='switch-'+uuid4().hex))
    def case(self,kind='collection',**changes):
        p=dict(kind=kind,customer='UAT S9 Sintetis',region_id='SMG',difficulty='Medium',amount=5000000)
        if kind=='origination':p.update(income=10000000,interest=4)
        else:p['dpd']=15
        p.update(changes);return self.call('POST','/api/cases',p,201)['id']
    def detail(self,cid):return self.call('GET','/api/cases/'+cid)
    def assign(self,cid):return self.call('POST','/api/assignments',dict(case_ids=[cid]))
    def activity(self,cid,code,**kw):
        return self.call('POST','/api/cases/'+cid+'/activities',dict(code=code,expected_version=self.detail(cid)['case']['version'],request_key=uuid4().hex,**kw))
    def reassign(self,cid,status=200):
        return self.call('POST','/api/cases/'+cid+'/reassign',dict(expected_version=self.detail(cid)['case']['version'],reason='Siklus baru untuk pengujian model'),status)

    def test_frozen_artifact_reproducibility_and_test_never_fits_parameters(self):
        altered=copy.deepcopy(self.samples)
        for row in altered:
            if row['split']=='test':row['label']=1-row['label'];row['features']['amount']=10**12
        artifact,report=train_release(altered,self.artifact['provenance'])
        self.assertEqual(artifact,self.artifact)
        self.assertNotEqual(report['models'][0]['evaluation']['test'],self.release['report']['models'][0]['evaluation']['test'])
        self.assertEqual(content_hash(artifact),self.release['artifact_sha256'])

    def test_train_only_scaling_and_validation_calibration_identity_partition(self):
        for key,m in self.artifact['models'].items():
            train=[s for s in self.samples if s['kind']==m['kind'] and s['stage']==m['stage'] and s['split']=='train']
            index=m['numeric'].index('amount')
            self.assertAlmostEqual(m['means'][index],sum(s['features']['amount'] for s in train)/len(train))
            from app.model_engine import calibration_partitions
            cal,selection,_=calibration_partitions([s for s in self.samples if s['kind']==m['kind'] and s['stage']==m['stage'] and s['split']=='validation'])
            self.assertFalse({s['entity_id'] for s in cal}&{s['entity_id'] for s in selection})
            for row in train[:10]:self.assertTrue(0<infer(m,row['features'])<1)

    def test_initial_assignment_predictions_are_frozen_and_reassignment_uses_closed_payments(self):
        self.activate();cid=self.case();preview=self.detail(cid)['prediction'];self.assertEqual(preview['source'],'ml_simulation')
        self.assertEqual(preview['model_key'],'collection_initial');self.assertEqual(preview['features']['age_days'],0)
        self.assign(cid);first=self.detail(cid)['prediction'];self.assertEqual(first['source'],'ml_simulation')
        self.assertEqual(self.detail(cid)['case']['agent_id'],'SMG-col-B')
        self.activity(cid,'unreachable');self.activity(cid,'payment',amount=1500000)
        self.assertEqual(self.detail(cid)['prediction'],first)
        self.now+=timedelta(days=3);self.h=self.login('supervisor');self.reassign(cid)
        result=self.detail(cid);p=result['prediction'];self.assertEqual(p['source'],'ml_simulation',p['reason'])
        self.assertEqual(p['model_key'],'collection_reassignment');self.assertEqual(p['features']['closed_cycles'],1)
        self.assertEqual(p['features']['paid_before_decision'],1500000);self.assertEqual(p['features']['remaining_at_decision'],3500000)
        self.assertEqual(result['assignments'][0]['prediction'],first)
        self.assertLessEqual(p['feature_max_at'],p['decision_at'])

    def test_origination_origin_documents_remain_predecision_and_window_is_30_days(self):
        self.activate();cid=self.case('origination');self.assign(cid);initial=self.detail(cid)['prediction']
        self.assertEqual(initial['source'],'ml_simulation');self.assertEqual(initial['horizon'],30)
        self.activity(cid,'documents');self.activity(cid,'qualified')
        self.assertEqual(self.detail(cid)['prediction'],initial)
        self.now+=timedelta(days=10);self.h=self.login('supervisor');self.reassign(cid)
        p=self.detail(cid)['prediction'];self.assertEqual(p['source'],'ml_simulation',p['reason'])
        self.assertEqual(p['features']['documents_complete'],0);self.assertEqual(p['features']['previous_documents'],1)
        self.assertEqual(p['features']['previous_qualified'],1)
        self.activity(cid,'disburse',amount=5000000);self.assertEqual(self.detail(cid)['case']['status'],'disbursed')

    def test_fallback_for_legacy_missing_snapshot_new_region_and_out_of_range(self):
        self.activate();cid=self.case()
        with self.app.state.db.connect(write=True) as conn:conn.execute('DELETE FROM case_origins WHERE case_id=?',(cid,))
        p=self.detail(cid)['prediction'];self.assertEqual(p['source'],'rules');self.assertIn('kasus lama',p['reason'])
        self.assign(cid);self.assertEqual(self.detail(cid)['case']['score_version'],'rules-demo-v1')
        self.call('POST','/api/master/regions',dict(id='YOG',name='Yogyakarta'),201)
        p=self.detail(self.case(region_id='YOG'))['prediction'];self.assertIn('Kategori belum dikenal',p['reason'])
        p=self.detail(self.case(dpd=3650))['prediction'];self.assertIn('di luar rentang',p['reason'])

    def test_low_high_hard_constraints_survive_models_and_capacity_rollback(self):
        self.activate()
        for difficulty,team in [('Low','A'),('High','B')]:
            cid=self.case(difficulty=difficulty);self.assign(cid)
            self.assertTrue(self.detail(cid)['case']['agent_id'].endswith(team))
        cid=self.case();self.assign(cid);before=self.detail(cid)
        for aid in ['SMG-col-A','SMG-col-B']:self.call('PATCH','/api/agents/'+aid,dict(capacity=12,active=False))
        self.reassign(cid,409)
        after=self.detail(cid)
        for name in ('case','assignments','activities','prediction'):self.assertEqual(before[name],after[name])

    def test_batch_priority_uses_current_model_and_keeps_capacity_atomic(self):
        self.activate()
        cases=[self.case(difficulty='Low',amount=amount) for amount in (2000000,5000000,10000000,30000000,50000000)]
        probabilities={cid:self.detail(cid)['prediction']['probability'] for cid in cases}
        self.assertGreater(len(set(probabilities.values())),1)
        expected=max(cases,key=lambda cid:probabilities[cid])
        self.call('PATCH','/api/agents/SMG-col-A',dict(capacity=1,active=True))
        result=self.call('POST','/api/assignments',dict(case_ids=list(reversed(cases))))
        self.assertEqual([r['case_id'] for r in result['results'] if r['assigned']],[expected])
        with self.app.state.db.connect() as conn:self.assertEqual(conn.execute('SELECT count(*) FROM ml_predictions').fetchone()[0],1)

    def test_activation_rollback_stale_revision_concurrent_retry_and_history(self):
        payload=dict(release_id=self.release['id'],expected_revision=0,demo_ack=True,reason='Aktivasi atomik model sintetis',request_key='race-'+uuid4().hex)
        with ThreadPoolExecutor(max_workers=2) as pool:results=list(pool.map(lambda _:self.client.post('/api/models/serving',headers=self.h,json=payload),range(2)))
        self.assertEqual([r.status_code for r in results],[200,200]);self.assertEqual(self.call('GET','/api/models/serving')['revision'],1)
        stale={**payload,'request_key':'stale-'+uuid4().hex}
        self.call('POST','/api/models/serving',stale,409)
        self.activate(False);state=self.call('GET','/api/models/serving');self.assertEqual(state['revision'],2);self.assertIsNone(state['release_id'])
        self.assertEqual(len(state['history']),2)
        self.call('POST','/api/models/serving',{**payload,'request_key':'ack-'+uuid4().hex,'expected_revision':2,'demo_ack':False},422)

    def test_override_checks_serving_revision_and_read_only_preview(self):
        self.activate();cid=self.case();options=self.call('GET','/api/cases/'+cid+'/assignment-options')
        self.assertEqual(options['prediction']['source'],'ml_simulation')
        with self.app.state.db.connect() as conn:self.assertEqual(conn.execute('SELECT count(*) FROM ml_predictions').fetchone()[0],0)
        chosen=next(a['agent_id'] for a in options['options'] if a['eligible'])
        self.activate(False)
        self.call('POST','/api/cases/'+cid+'/override-assignment',dict(agent_id=chosen,expected_version=options['expected_version'],
            expected_scoring_revision=options['expected_scoring_revision'],reason='Override dengan preview sebelumnya',request_key=uuid4().hex),409)

    def test_corrupt_artifact_blocks_activation_export_and_serves_rules(self):
        self.activate()
        with self.app.state.db.connect(write=True) as conn:conn.execute("UPDATE ml_releases SET artifact='{}' WHERE id=?",(self.release['id'],))
        self.assertEqual(self.call('GET','/api/models/serving')['status'],'invalid_fallback')
        cid=self.case();p=self.detail(cid)['prediction'];self.assertEqual(p['source'],'rules');self.assertIn('tidak valid',p['reason'])
        self.call('POST','/api/models/serving',dict(release_id=self.release['id'],expected_revision=1,demo_ack=True,reason='Uji penolakan artefak korup',request_key=uuid4().hex),409)
        self.assertEqual(self.client.get('/api/models/'+self.release['id']+'/export',headers=self.h).status_code,409)

    def test_training_retry_idempotency_insufficient_data_and_corrupt_dataset(self):
        payload=dict(run_id=self.dataset['id'],request_key='train-'+uuid4().hex)
        a=self.call('POST','/api/models/train',payload,201);b=self.call('POST','/api/models/train',payload,201);self.assertEqual(a['id'],b['id']);self.assertTrue(b['replayed'])
        self.call('POST','/api/models/train',{**payload,'run_id':'HIST-MISSING'},409)
        small=self.call('POST','/api/analytics/runs',dict(cases_per_kind=100,request_key='small-'+uuid4().hex),201)
        self.call('POST','/api/models/train',dict(run_id=small['id'],request_key=uuid4().hex),422)
        with self.app.state.db.connect(write=True) as conn:conn.execute("UPDATE analytics_cases SET payload='{}' WHERE run_id=?",(self.dataset['id'],))
        self.call('POST','/api/models/train',dict(run_id=self.dataset['id'],request_key=uuid4().hex),422)

    def test_training_and_serving_writes_are_atomic_on_audit_failure(self):
        with patch('app.models.audit',side_effect=RuntimeError('Injected audit failure')):
            with self.assertRaises(RuntimeError):self.activate()
            with self.assertRaises(RuntimeError):self.call('POST','/api/models/train',dict(run_id=self.dataset['id'],request_key=uuid4().hex),201)
        self.assertEqual(self.call('GET','/api/models')['total'],1);self.assertEqual(self.call('GET','/api/models/serving')['revision'],0)

    def test_export_portable_json_provenance_and_restart(self):
        self.activate();cid=self.case();self.assign(cid);before=self.detail(cid)
        response=self.client.get('/api/models/'+self.release['id']+'/export',headers=self.h)
        self.assertEqual(response.status_code,200);self.assertEqual(response.headers['content-type'],'application/zip')
        self.assertEqual(response.headers['cache-control'],'no-store')
        with zipfile.ZipFile(io.BytesIO(response.content)) as z:
            self.assertEqual(set(z.namelist()),{'model.json','report.json'})
            artifact=json.loads(z.read('model.json'));self.assertEqual(content_hash(artifact),self.release['artifact_sha256'])
            self.assertEqual(artifact['provenance']['data_sha256'],self.dataset['manifest']['data_sha256'])
        with TestClient(create_app(str(self.path),lambda:self.now)) as restarted:
            self.assertEqual(restarted.get('/api/cases/'+cid,headers=self.h).json(),before)
            self.assertEqual(restarted.get('/api/models/serving',headers=self.h).json()['release_id'],self.release['id'])

    def test_registry_pagination_supervisor_role_and_no_cache(self):
        routes=[('GET','/api/models'),('GET','/api/models/serving'),('POST','/api/models/serving'),('POST','/api/models/train'),
            ('GET','/api/models/'+self.release['id']),('GET','/api/models/'+self.release['id']+'/export')]
        agent=self.login('smg-col-a')
        for method,path in routes:
            self.assertEqual(self.client.request(method,path).status_code,401)
            self.assertEqual(self.client.request(method,path,headers=agent).status_code,403)
        self.assertEqual(self.call('GET','/api/models?offset=1&limit=1')['items'],[])
        self.assertEqual(self.client.get('/api/models?limit=101',headers=self.h).status_code,422)
        self.call('GET','/api/models/MISSING',status=404)
