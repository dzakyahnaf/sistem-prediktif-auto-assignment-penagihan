import copy,json,unittest
from datetime import timedelta
from concurrent.futures import ThreadPoolExecutor
from unittest.mock import patch
from uuid import uuid4
from fastapi.testclient import TestClient
import test_models as fixtures
from app.main import create_app
from app.segments import train_segments,segment_infer
from app.historical import content_hash

class DecisionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        fixtures.ModelTests.setUpClass.__func__(cls)
        with TestClient(create_app(str(cls.base),lambda:cls.now)) as client:
            h={'Authorization':'Bearer '+client.post('/api/auth/login',json=dict(username='supervisor',password='DemoAssignment!2026')).json()['access_token']}
            r=client.post('/api/decisions/segments',headers=h,json=dict(model_id=cls.release['id'],request_key='segments-test-fixture'))
            assert r.status_code==201,r.text;cls.segment=r.json()
            with client.app.state.db.connect() as c:cls.seg_artifact=json.loads(c.execute('SELECT artifact FROM segment_releases').fetchone()[0])
    tearDownClass=classmethod(fixtures.ModelTests.tearDownClass.__func__)
    setUp=fixtures.ModelTests.setUp
    tearDown=fixtures.ModelTests.tearDown
    login=fixtures.ModelTests.login
    call=fixtures.ModelTests.call
    case=fixtures.ModelTests.case
    detail=fixtures.ModelTests.detail
    assign=fixtures.ModelTests.assign
    activity=fixtures.ModelTests.activity
    activate=fixtures.ModelTests.activate
    def policy(self,**changes):
        old=self.call('GET','/api/decisions')['policy'];cfg={**old['config'],**changes}
        return dict(config=cfg,expected_revision=old['revision'],reason='Kebijakan pengujian sintetis terpadu',request_key='policy-'+uuid4().hex)
    def publish(self,**changes):return self.call('POST','/api/decisions/policy',self.policy(**changes))

    def test_segments_train_only_deterministic_no_outcome_predictors(self):
        altered=copy.deepcopy(self.samples)
        for r in altered:
            r['label']=1-(r['label'] or 0)
            if r['split']!='train':r['features']['amount']*=10
        artifact,report=train_segments(self.artifact,altered)
        self.assertEqual(artifact,self.seg_artifact)
        self.assertEqual(len(report['models']),4)
        for m in report['models']:
            self.assertIn(m['k'],[2,3,4]);self.assertEqual(len(m['stability_ari']),3)
            self.assertEqual(sum(p['n'] for p in m['profiles']),m['subsets']['train']['n'])

    def test_policy_routes_medium_hard_low_high_and_freezes_existing_decision(self):
        before=self.case();self.assign(before);old=self.detail(before)['prediction']
        self.publish(medium_threshold=90,collection_followup_hours=24,collection_base=90)
        for difficulty,team in [('Medium','B'),('Low','A'),('High','B')]:
            cid=self.case(difficulty=difficulty);d=self.detail(cid)
            self.assertEqual(d['target_team'],team);self.assertEqual(d['prediction']['policy']['revision'],1)
            self.assign(cid);d=self.detail(cid)
            self.assertEqual(d['case']['score_version'],'rules-policy-v1')
            self.assertEqual(d['case']['due_at'],(self.now+timedelta(hours=24)).isoformat(timespec='seconds'))
        self.assertEqual(self.detail(before)['prediction'],old)
        self.assertEqual(self.call('GET','/api/config')['collection_success_hours'],72)

    def test_success_72h_independent_of_followup_hours_and_terminal_late(self):
        self.publish(collection_followup_hours=24)
        cid=self.case(difficulty='Low');self.assign(cid);self.now+=timedelta(hours=48);self.h=self.login('supervisor')
        self.activity(cid,'payment',amount=5000000)
        self.assertEqual(self.detail(cid)['assignments'][-1]['outcome'],'success')
        self.publish(collection_followup_hours=168)
        cid=self.case(difficulty='Low');self.assign(cid);self.now+=timedelta(hours=73);self.h=self.login('supervisor')
        self.activity(cid,'payment',amount=5000000)
        self.assertEqual(self.detail(cid)['assignments'][-1]['outcome'],'no_success')

    def test_batch_priority_recomputes_current_rules_after_policy_change(self):
        high_old=self.case('origination',difficulty='Low',amount=10000000,income=1000000,interest=5)
        high_new=self.case('origination',difficulty='Low',amount=10000000,income=10000000,interest=1,documents_complete=True)
        self.assertGreater(self.detail(high_old)['case']['score'],self.detail(high_new)['case']['score'])
        self.publish(interest_weight=0,document_bonus=25,income_bonus=20)
        self.call('PATCH','/api/agents/SMG-ori-A',dict(capacity=1,active=True))
        result=self.call('POST','/api/assignments',dict(case_ids=[high_old,high_new]))['results']
        self.assertEqual(result[0]['case_id'],high_new);self.assertTrue(result[0]['assigned']);self.assertFalse(result[1]['assigned'])

    def test_segments_and_explanations_snapshot_and_out_of_domain_fallback(self):
        self.activate();self.publish(segment_release_id=self.segment['id'])
        cid=self.case();p=self.detail(cid)['prediction'];self.assertEqual(p['segment']['status'],'ready')
        self.assertEqual(len(p['explanation']),4);self.assign(cid);snap=self.detail(cid)['prediction']
        self.publish(segment_release_id=None,medium_threshold=65)
        self.assertEqual(self.detail(cid)['prediction'],snap)
        cid=self.case(dpd=3650);p=self.detail(cid)['prediction'];self.assertEqual(p['source'],'rules')
        self.publish(segment_release_id=self.segment['id']);p=self.detail(cid)['prediction'];self.assertEqual(p['segment']['status'],'unavailable')
        with self.app.state.db.connect(write=True) as c:c.execute('DELETE FROM case_origins WHERE case_id=?',(cid,))
        self.assertEqual(self.detail(cid)['prediction']['segment']['status'],'unavailable')

    def test_policy_idempotency_concurrency_stale_revision_validation_and_role(self):
        p=self.policy()
        def post():return self.client.post('/api/decisions/policy',headers=self.h,json=p)
        with ThreadPoolExecutor(max_workers=2) as pool:responses=list(pool.map(lambda _:post(),range(2)))
        self.assertEqual([r.status_code for r in responses],[200,200]);self.assertEqual(sum(r.json()['replayed'] for r in responses),1)
        changed={**p,'reason':'Payload berubah untuk key sama'};self.call('POST','/api/decisions/policy',changed,409)
        self.call('POST','/api/decisions/policy',{**p,'request_key':uuid4().hex},409)
        for field,value in [('medium_threshold',100),('collection_followup_hours',0),('dpd_penalty',-1),('origination_followup_hours',1.5)]:
            bad=self.policy();bad['config'][field]=value;self.call('POST','/api/decisions/policy',bad,422)
        agent=self.login('smg-col-a')
        for method,path,body in [('GET','/api/decisions',None),('POST','/api/decisions/policy',self.policy()),('POST','/api/decisions/segments',dict(model_id=self.release['id'],request_key=uuid4().hex))]:
            self.assertEqual(self.client.request(method,path,headers=agent,json=body).status_code,403)

    def test_preview_revision_conflict_and_policy_audit_rollback(self):
        cid=self.case();options=self.call('GET','/api/cases/'+cid+'/assignment-options')
        chosen=next(x['agent_id'] for x in options['options'] if x['eligible'])
        self.publish(medium_threshold=61)
        self.call('POST','/api/cases/'+cid+'/override-assignment',dict(agent_id=chosen,expected_version=options['expected_version'],expected_policy_revision=options['expected_policy_revision'],request_key=uuid4().hex,reason='Override stale policy ditolak'),409)
        revision=self.call('GET','/api/decisions')['policy']['revision']
        with patch('app.decisions.audit',side_effect=RuntimeError('injected')):
            with self.assertRaises(RuntimeError):self.client.post('/api/decisions/policy',headers=self.h,json=self.policy())
        self.assertEqual(self.call('GET','/api/decisions')['policy']['revision'],revision)

    def test_training_retry_corruption_and_restart(self):
        p=dict(model_id=self.release['id'],request_key=uuid4().hex)
        a=self.call('POST','/api/decisions/segments',p,201);b=self.call('POST','/api/decisions/segments',p,201)
        self.assertEqual(a['id'],b['id']);self.assertTrue(b['replayed'])
        self.publish(segment_release_id=a['id'])
        with TestClient(create_app(str(self.path),lambda:self.now)) as again:
            r=again.get('/api/decisions',headers=self.h);self.assertEqual(r.status_code,200);self.assertEqual(r.json()['policy']['revision'],1)
        with self.app.state.db.connect(write=True) as c:c.execute('UPDATE segment_releases SET artifact_sha256=? WHERE id=?',('bad',a['id']))
        self.call('POST','/api/decisions/policy',self.policy(segment_release_id=a['id']),409)
        self.assertEqual(self.detail(self.case())['prediction']['segment']['status'],'unavailable')
