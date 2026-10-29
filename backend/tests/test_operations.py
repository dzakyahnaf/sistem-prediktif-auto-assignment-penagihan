import json,unittest
from concurrent.futures import ThreadPoolExecutor
from datetime import timedelta
from unittest.mock import patch
from uuid import uuid4
from fastapi.testclient import TestClient
import test_workflows as fixtures
from app.main import create_app

class OperationsTests(unittest.TestCase):
    setUpClass=classmethod(fixtures.WorkflowTests.setUpClass.__func__)
    tearDownClass=classmethod(fixtures.WorkflowTests.tearDownClass.__func__)
    setUp=fixtures.WorkflowTests.setUp
    tearDown=fixtures.WorkflowTests.tearDown
    login=fixtures.WorkflowTests.login
    create=fixtures.WorkflowTests.create
    assign=fixtures.WorkflowTests.assign
    activity=fixtures.WorkflowTests.activity
    get_case=fixtures.WorkflowTests.get_case
    def call(self,method,path,body=None,status=200,headers=None):
        r=self.client.request(method,path,json=body,headers=headers or self.headers);self.assertEqual(r.status_code,status,r.text);return r.json()
    def job(self,cid,scenario='success',channel='telephony',**extra):
        p=dict(scenario=scenario,channel=channel,expected_version=self.get_case(cid)['version'],request_key=uuid4().hex,**extra)
        return self.call('POST','/api/cases/'+cid+'/integrations',p,201)['job']
    def process(self,**extra):return self.call('POST','/api/integrations/process',dict(request_key=uuid4().hex,**extra))
    def account(self,username='smg-col-a'):
        return next(r for r in self.call('GET','/api/accounts')['items'] if r['username']==username)
    def edit_account(self,active=True,password=None,**extra):
        a=self.account();p=dict(active=active,new_password=password,expected_version=a['version'],reason='Kontrol akun petugas sintetis untuk UAT',request_key=uuid4().hex,**extra)
        return a,p

    def test_assignment_inbox_read_scope_and_reassignment_notification(self):
        cid=self.create(difficulty='Medium',dpd=15);self.assign([cid]);a=self.login('smg-col-a');b=self.login('smg-col-b')
        inbox=self.call('GET','/api/notifications',headers=a);self.assertEqual(inbox['unread'],1);n=inbox['items'][0]
        self.assertTrue(n['can_open']);self.assertNotIn('Pemohon Uji',n['body'])
        self.call('PATCH','/api/notifications/'+n['id']+'/read',headers=b,status=404)
        first=self.call('PATCH','/api/notifications/'+n['id']+'/read',headers=a);self.now+=timedelta(seconds=1)
        self.assertEqual(self.call('PATCH','/api/notifications/'+n['id']+'/read',headers=a),first)
        self.activity(cid,'unreachable');self.call('POST','/api/cases/'+cid+'/reassign',dict(expected_version=self.get_case(cid)['version'],reason='Alih tugas notifikasi dari A ke B'))
        self.assertFalse(self.call('GET','/api/notifications',headers=a)['items'][0]['can_open'])
        self.assertEqual(self.call('GET','/api/notifications',headers=b)['unread'],1)

    def test_enqueue_concurrent_idempotency_delivery_and_no_business_activity(self):
        cid=self.create();self.assign([cid]);before=self.get_case(cid)
        p=dict(channel='telephony',scenario='success',expected_version=before['version'],request_key=uuid4().hex)
        with ThreadPoolExecutor(max_workers=2) as pool:
            r=list(pool.map(lambda _:self.client.post('/api/cases/'+cid+'/integrations',headers=self.headers,json=p),range(2)))
        self.assertEqual([x.status_code for x in r],[201,201]);self.assertEqual(r[0].json()['job']['id'],r[1].json()['job']['id'])
        result=self.process();self.assertEqual(result['processed'],1);self.assertEqual(result['results'][0]['state'],'delivered')
        self.assertEqual(self.get_case(cid),before)
        self.assertEqual(self.process()['processed'],0)
        saved=self.call('POST','/api/cases/'+cid+'/integrations',p,201);self.assertTrue(saved['replayed']);self.assertEqual(saved['job']['state'],'delivered')
        self.call('POST','/api/cases/'+cid+'/integrations',{**p,'channel':'omnichannel'},409)

    def test_fail_once_backoff_then_receipt_and_process_retry_key(self):
        cid=self.create();self.assign([cid]);job=self.job(cid,'fail_once','omnichannel')
        p=dict(request_key=uuid4().hex,limit=20);one=self.call('POST','/api/integrations/process',p)
        self.assertEqual(one['results'][0]['state'],'retry');self.assertEqual(self.process()['processed'],0)
        self.now+=timedelta(seconds=15)
        self.assertTrue(self.call('POST','/api/integrations/process',p)['replayed'])
        self.assertEqual(self.process()['results'][0]['state'],'delivered')
        current=self.call('GET','/api/integrations')['items'][0];self.assertEqual(current['receipt_id'],'MOCK-'+job['id']);self.assertEqual(current['attempts'],2)

    def test_dead_letter_manual_recovery_preserves_attempts_and_version(self):
        cid=self.create();self.assign([cid]);job=self.job(cid,'fail_always')
        for i in range(3):
            result=self.process();self.assertEqual(result['processed'],1);self.now+=timedelta(minutes=5)
        job=self.call('GET','/api/integrations')['items'][0];self.assertEqual(job['state'],'dead');self.assertEqual(job['attempts'],3)
        p=dict(expected_version=job['version'],scenario='success',reason='Pulihkan adapter mock yang sebelumnya gagal',request_key=uuid4().hex)
        self.call('POST','/api/integrations/'+job['id']+'/retry',p)
        self.assertTrue(self.call('POST','/api/integrations/'+job['id']+'/retry',p)['replayed'])
        self.call('POST','/api/integrations/'+job['id']+'/retry',{**p,'request_key':uuid4().hex},409)
        self.assertEqual(self.process()['results'][0]['attempt'],4)
        current=self.call('GET','/api/integrations')['items'][0];self.assertEqual(len(current['attempt_history']),4);self.assertEqual(current['state'],'delivered')

    def test_stale_cycle_terminal_and_disabled_account_cancel_pending(self):
        cid=self.create();self.assign([cid]);self.job(cid)
        self.call('POST','/api/cases/'+cid+'/reassign',dict(expected_version=self.get_case(cid)['version'],reason='Siklus lama tidak boleh mengirim job tertunda'))
        self.assertEqual(self.process()['results'][0]['state'],'canceled')
        self.job(cid);self.activity(cid,'payment',amount=1000000)
        self.assertEqual(self.process()['results'][0]['state'],'canceled')
        cid=self.create();self.assign([cid]);self.job(cid)
        a,p=self.edit_account(False);self.call('PATCH','/api/accounts/'+a['id'],p)
        self.assertEqual(self.process()['results'][0]['state'],'canceled')

    def test_worker_and_account_atomic_rollback_on_audit_failure(self):
        cid=self.create();self.assign([cid]);self.job(cid)
        with patch('app.operations.audit',side_effect=RuntimeError('injected')):
            with self.assertRaises(RuntimeError):self.process()
        job=self.call('GET','/api/integrations')['items'][0];self.assertEqual(job['state'],'pending');self.assertEqual(job['attempt_history'],[])
        a,p=self.edit_account(False,'NewDemoPassword!2026')
        with patch('app.operations.audit',side_effect=RuntimeError('injected')):
            with self.assertRaises(RuntimeError):self.call('PATCH','/api/accounts/'+a['id'],p)
        self.assertEqual(self.account()['version'],0);self.login('smg-col-a')

    def test_account_disable_revocation_routing_reset_replay_and_secrets(self):
        agent=self.login('smg-col-a');a,p=self.edit_account(False,'NewDemoPassword!2026')
        self.call('PATCH','/api/accounts/'+a['id'],p);self.assertTrue(self.call('PATCH','/api/accounts/'+a['id'],p)['replayed'])
        self.assertEqual(self.client.get('/api/me',headers=agent).status_code,401)
        self.assertEqual(self.client.post('/api/auth/login',json=dict(username='smg-col-a',password='NewDemoPassword!2026')).status_code,401)
        cid=self.create();self.assertFalse(self.assign([cid]).json()['results'][0]['assigned'])
        a,activate=self.edit_account(True);self.call('PATCH','/api/accounts/'+a['id'],activate)
        self.assertEqual(self.client.post('/api/auth/login',json=dict(username='smg-col-a',password='DemoAssignment!2026')).status_code,401)
        self.assertEqual(self.client.post('/api/auth/login',json=dict(username='smg-col-a',password='NewDemoPassword!2026')).status_code,200)
        self.assertTrue(self.assign([cid]).json()['results'][0]['assigned'])
        with self.app.state.db.connect() as c:
            audit=''.join(r[0] for r in c.execute('SELECT detail FROM audit'));payloads=''.join(r[0] for r in c.execute('SELECT payload FROM operation_requests'))
        self.assertNotIn('NewDemoPassword!2026',audit+payloads);self.assertNotIn('password_hash',audit)
        self.call('PATCH','/api/accounts/'+a['id'],{**p,'new_password':'DifferentPassword!2026'},409)

    def test_roles_scope_input_and_supervisor_account_guard(self):
        cid=self.create();self.assign([cid]);agent=self.login('smg-col-a');other=self.login('smg-col-b')
        p=dict(channel='telephony',scenario='success',expected_version=self.get_case(cid)['version'],request_key=uuid4().hex)
        self.call('POST','/api/cases/'+cid+'/integrations',p,404,headers=other)
        self.call('POST','/api/cases/'+cid+'/integrations',{**p,'scenario':'fail_once'},403,headers=agent)
        self.call('POST','/api/cases/'+cid+'/integrations',p,201,headers=agent)
        self.assertEqual(self.call('GET','/api/integrations',headers=other)['total'],0)
        self.assertEqual(self.call('GET','/api/integrations',headers=agent)['total'],1)
        self.call('POST','/api/integrations/process',dict(request_key=uuid4().hex),403,headers=agent)
        self.call('GET','/api/accounts',headers=agent,status=403)
        a,b=self.edit_account();self.call('PATCH','/api/accounts/'+a['id'],{**b,'new_password':'short'},422)
        with self.app.state.db.connect() as c:uid=c.execute("SELECT id FROM users WHERE role='supervisor'").fetchone()[0]
        self.call('PATCH','/api/accounts/'+uid,b,404)

    def test_sla_scan_is_deduplicated_read_and_does_not_finalize_outcome(self):
        cid=self.create();self.assign([cid]);before=self.get_case(cid)
        self.now+=timedelta(hours=73);self.headers=self.login('supervisor');agent=self.login('smg-col-a')
        p=dict(request_key=uuid4().hex);self.assertEqual(self.call('POST','/api/notifications/scan',p)['created'],1)
        self.assertTrue(self.call('POST','/api/notifications/scan',p)['replayed'])
        self.assertEqual(self.call('POST','/api/notifications/scan',dict(request_key=uuid4().hex))['created'],0)
        self.assertEqual(self.get_case(cid),before)
        self.assertEqual(self.call('GET','/api/notifications?unread=true&limit=1',headers=agent)['total'],2)

    def test_worker_concurrency_and_database_restart(self):
        cid=self.create();self.assign([cid]);self.job(cid)
        def process(_):return self.client.post('/api/integrations/process',headers=self.headers,json=dict(request_key=uuid4().hex))
        with ThreadPoolExecutor(max_workers=2) as pool:responses=list(pool.map(process,range(2)))
        self.assertEqual([r.status_code for r in responses],[200,200]);self.assertEqual(sum(r.json()['processed'] for r in responses),1)
        with TestClient(create_app(str(self.path),lambda:self.now)) as again:
            r=again.get('/api/integrations',headers=self.headers);self.assertEqual(r.status_code,200);self.assertEqual(r.json()['items'][0]['state'],'delivered')
