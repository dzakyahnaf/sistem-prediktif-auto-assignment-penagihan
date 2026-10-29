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
from app.historical import HistoryConfig, build_samples, content_hash, create_dataset, simulate, validate_bundle, FEATURES
from app.migrate import digest
from app.seed import DEMO_PASSWORD
from app.domain import timestamp


class AnalyticsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory()
        cls.base = Path(cls.temp.name)/'base.db'
        with TestClient(create_app(str(cls.base))): pass

    @classmethod
    def tearDownClass(cls): cls.temp.cleanup()

    def setUp(self):
        self.path = Path(self.temp.name)/(uuid4().hex+'.db'); shutil.copy2(self.base, self.path)
        self.now = datetime(2026, 10, 28, tzinfo=timezone.utc)
        self.app = create_app(str(self.path), lambda:self.now)
        self.client = TestClient(self.app).__enter__(); self.h = self.login('supervisor')

    def tearDown(self): self.client.__exit__(None, None, None)

    def login(self, username):
        r = self.client.post('/api/auth/login', json=dict(username=username, password=DEMO_PASSWORD))
        self.assertEqual(r.status_code, 200, r.text)
        return {'Authorization':'Bearer '+r.json()['access_token']}

    def generate(self, **changes):
        payload = dict(cases_per_kind=300, request_key='history-'+uuid4().hex, **changes)
        r = self.client.post('/api/analytics/runs', headers=self.h, json=payload)
        self.assertEqual(r.status_code, 201, r.text)
        return r.json(), payload

    def snapshot(self):
        with self.app.state.db.connect() as conn:
            return {n:digest(conn.execute('SELECT * FROM '+n).fetchall()) for n in ('cases','assignments','activities','agents','regions','users','import_batches','import_case_refs','assignment_overrides')}

    def raw(self, kind='collection', at='2025-01-01T00:00:00+00:00'):
        case = dict(id='C1', entity_id='E1', kind=kind, amount=100, region_id='SMG', difficulty='Medium',
                    dpd=10, income=1000, interest=3, documents_complete=0, created_at=timestamp(datetime.fromisoformat(at)-timedelta(hours=1)))
        decision = dict(id='D1', case_id='C1', cycle=1, assigned_at=at, closed_at=timestamp(datetime.fromisoformat(at)+timedelta(days=45)),
                        outcome='open', team='A', assignment_propensity=.5)
        return dict(cases=[case], decisions=[decision], events=[])

    def event(self, raw, hours, code, amount=0, decision='D1'):
        when = next(d['assigned_at'] for d in raw['decisions'] if d['id']==decision)
        raw['events'].append(dict(id='EV'+str(len(raw['events'])), decision_id=decision,
            at=timestamp(datetime.fromisoformat(when)+timedelta(hours=hours)), code=code, amount=amount))

    def test_default_reproducibility_four_datasets_and_quality(self):
        a,m = create_dataset(HistoryConfig()); b,n = create_dataset(HistoryConfig())
        self.assertEqual(a,b); self.assertEqual(m,n); self.assertEqual(m['counts']['cases'],6000)
        self.assertTrue(all(d['demo_training_ready'] for d in m['datasets']))
        self.assertEqual(len(m['datasets']),4)
        self.assertNotEqual(m['data_sha256'],create_dataset(HistoryConfig(seed=12))[1]['data_sha256'])
        for s in a['samples']:
            self.assertEqual(set(s['features']),set(FEATURES[s['kind']][s['stage']]))
            self.assertLessEqual(s['feature_max_at'],s['decision_at'])
            self.assertFalse({'label','team','assignment_propensity','entity_id','outcome'} & set(s['features']))

    def test_collection_full_partial_late_and_exact_72_hour_labels(self):
        config=HistoryConfig()
        for full_hour, expected in [(72,1),(73,0),(None,0)]:
            raw=self.raw(); self.event(raw,24,'payment',25)
            if full_hour: self.event(raw,full_hour,'payment',75)
            sample=build_samples(raw,config)[0]
            self.assertEqual(sample['label'],expected);self.assertEqual(sample['split'],'train')

    def test_origination_conversion_window_is_separate_from_sla(self):
        for hour,expected in [(72,1),(30*24,1),(30*24+1,0)]:
            raw=self.raw('origination');self.event(raw,hour,'disburse',100)
            self.assertEqual(build_samples(raw,HistoryConfig())[0]['label'],expected)
        raw=self.raw('origination');self.event(raw,48,'reject')
        self.assertEqual(build_samples(raw,HistoryConfig())[0]['label'],0)

    def test_current_cycle_cannot_change_features_and_reassignment_uses_closed_history(self):
        raw=self.raw();self.event(raw,12,'unreachable');self.event(raw,24,'payment',25)
        first=build_samples(raw,HistoryConfig())[0]
        raw['decisions'][0].update(closed_at='2025-01-05T00:00:00+00:00',outcome='transferred')
        raw['decisions'].append(dict(**{**raw['decisions'][0], 'id':'D2','cycle':2,'assigned_at':'2025-01-05T00:01:00+00:00','closed_at':'2025-01-08T00:01:00+00:00','outcome':'payment'}))
        self.event(raw,72,'payment',75,decision='D2')
        samples=build_samples(raw,HistoryConfig()); s2=samples[1]
        self.assertEqual(first['features'],samples[0]['features']); self.assertEqual(s2['features']['paid_before_decision'],25)
        self.assertEqual(s2['features']['remaining_at_decision'],75);self.assertEqual(s2['features']['previous_unreachable'],1)
        self.assertEqual(s2['label'],1)
        changed=copy.deepcopy(raw);self.event(changed,8,'contacted',decision='D2')
        self.assertEqual(build_samples(changed,HistoryConfig())[1]['features'],s2['features'])

    def test_censoring_early_transfer_label_boundary_and_entity_purge(self):
        config=HistoryConfig()
        raw=self.raw(at='2026-09-30T00:00:00+00:00')
        self.assertEqual(build_samples(raw,config)[0]['exclusion'],'censored')
        raw=self.raw();raw['decisions'][0].update(closed_at='2025-01-02T00:00:00+00:00',outcome='transferred')
        sample=build_samples(raw,config)[0];self.assertIsNone(sample['label']);self.assertEqual(sample['exclusion'],'early_reassignment')
        raw=self.raw(at='2026-01-31T00:00:00+00:00');self.assertEqual(build_samples(raw,config)[0]['exclusion'],'label_cross_boundary')
        raw=self.raw(); other=self.raw(at='2026-03-01T00:00:00+00:00')
        other['cases'][0]['id']='C2';other['decisions'][0].update(id='D2',case_id='C2')
        raw['cases']+=other['cases'];raw['decisions']+=other['decisions']
        self.assertTrue(all(s['exclusion']=='entity_cross_split' for s in build_samples(raw,config)))

    def test_quality_gate_rejects_future_events_duplicate_ids_and_modified_features(self):
        config=HistoryConfig(cases_per_kind=100);raw=simulate(config);samples=build_samples(raw,config)
        corrupt=copy.deepcopy(raw);corrupt['events'][0]['at']='2030-01-01T00:00:00+00:00'
        with self.assertRaises(ValueError):validate_bundle(corrupt,samples,config)
        corrupt=copy.deepcopy(samples);corrupt[0]['features']['label']=1
        with self.assertRaises(ValueError):validate_bundle(raw,corrupt,config)
        corrupt=copy.deepcopy(raw);corrupt['cases'].append(corrupt['cases'][0])
        with self.assertRaises(ValueError):validate_bundle(corrupt,samples,config)

    def test_supervisor_only_and_validation(self):
        run,_=self.generate()
        paths=[('GET','/api/analytics/runs'),('POST','/api/analytics/runs'),('GET','/api/analytics/runs/'+run['id']),('GET','/api/analytics/runs/'+run['id']+'/samples'),('GET','/api/analytics/runs/'+run['id']+'/export')]
        for method,path in paths:
            self.assertEqual(self.client.request(method,path).status_code,401)
            self.assertEqual(self.client.request(method,path,headers=self.login('smg-col-a')).status_code,403)
        for changes in [dict(cases_per_kind=99),dict(cases_per_kind=5001),dict(seed=True),dict(as_of='2026-02-30'),dict(as_of='2027-10-01'),dict(train_until='2026-07-01'),dict(origination_window_days=2)]:
            r=self.client.post('/api/analytics/runs',headers=self.h,json=dict(request_key='key-'+uuid4().hex,**changes))
            self.assertEqual(r.status_code,422,r.text)

    def test_idempotent_concurrent_generation_conflict_and_operational_isolation(self):
        before=self.snapshot();payload=dict(cases_per_kind=100,request_key='concurrent-'+uuid4().hex)
        with ThreadPoolExecutor(max_workers=2) as pool:
            responses=list(pool.map(lambda _:self.client.post('/api/analytics/runs',headers=self.h,json=payload),range(2)))
        self.assertTrue(all(r.status_code==201 for r in responses))
        self.assertEqual(len({r.json()['id'] for r in responses}),1)
        payload['seed']=12
        self.assertEqual(self.client.post('/api/analytics/runs',headers=self.h,json=payload).status_code,409)
        self.assertEqual(self.snapshot(),before)
        with self.app.state.db.connect() as conn:
            self.assertEqual(conn.execute("SELECT count(*) FROM audit WHERE action='analytics_generate'").fetchone()[0],1)

    def test_paging_complete_archive_hash_and_restart(self):
        run,_=self.generate();base='/api/analytics/runs/'+run['id']
        first=self.client.get(base+'/samples',headers=self.h).json()
        second=self.client.get(base+'/samples?offset=25',headers=self.h).json()
        self.assertEqual(first['total'],300);self.assertEqual(len(first['items']),25)
        self.assertNotEqual(first['items'][0]['id'],second['items'][0]['id'])
        self.assertEqual(self.client.get(base+'/samples?kind=other',headers=self.h).status_code,422)
        self.assertEqual(self.client.get('/api/analytics/runs/MISSING',headers=self.h).status_code,404)
        exported=self.client.get(base+'/export',headers=self.h)
        self.assertEqual(exported.status_code,200,exported.text[:100] if exported.status_code!=200 else '')
        self.assertEqual(exported.headers['content-type'],'application/zip');self.assertEqual(exported.headers['cache-control'],'no-store')
        with zipfile.ZipFile(io.BytesIO(exported.content)) as archive:
            self.assertEqual(set(archive.namelist()),{'cases.jsonl','decisions.jsonl','events.jsonl','samples.jsonl','dictionary.json','manifest.json'})
            data={n:[json.loads(line) for line in archive.read(n+'.jsonl').splitlines()] for n in ('cases','decisions','events','samples')}
            self.assertEqual(len(data['cases']),600);self.assertEqual(content_hash(data),run['manifest']['data_sha256'])
        with TestClient(create_app(str(self.path),lambda:self.now)) as restarted:
            self.assertEqual(restarted.get(base,headers=self.h).json()['manifest'],run['manifest'])

    def test_failed_generation_rolls_back_and_retry_succeeds(self):
        payload=dict(cases_per_kind=100,request_key='rollback-'+uuid4().hex)
        with patch('app.analytics.audit',side_effect=RuntimeError('Injected write failure')):
            with self.assertRaises(RuntimeError):self.client.post('/api/analytics/runs',headers=self.h,json=payload)
        with self.app.state.db.connect() as conn:
            for n in ('runs','cases','decisions','events','samples'):
                self.assertEqual(conn.execute('SELECT COUNT(*) FROM analytics_'+n).fetchone()[0],0)
        self.assertEqual(self.client.post('/api/analytics/runs',headers=self.h,json=payload).status_code,201)

    def test_archive_corruption_blocks_export_without_audit(self):
        run,_=self.generate()
        with self.app.state.db.connect(write=True) as conn:
            conn.execute("UPDATE analytics_cases SET payload='{}' WHERE run_id=?",(run['id'],))
        self.assertEqual(self.client.get('/api/analytics/runs/'+run['id']+'/export',headers=self.h).status_code,409)
        with self.app.state.db.connect() as conn:
            self.assertEqual(conn.execute("SELECT count(*) FROM audit WHERE action='analytics_export'").fetchone()[0],0)
