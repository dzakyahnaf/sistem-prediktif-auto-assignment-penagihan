import json,tempfile,unittest
from pathlib import Path
from datetime import timedelta
from concurrent.futures import ThreadPoolExecutor
from fastapi.testclient import TestClient
import test_workflows as fixtures
from app.main import create_app

class HardeningTests(unittest.TestCase):
    setUpClass=classmethod(fixtures.WorkflowTests.setUpClass.__func__)
    tearDownClass=classmethod(fixtures.WorkflowTests.tearDownClass.__func__)
    setUp=fixtures.WorkflowTests.setUp
    tearDown=fixtures.WorkflowTests.tearDown
    login=fixtures.WorkflowTests.login
    def attempt(self,username='supervisor',password='wrong',headers=None):
        return self.client.post('/api/auth/login',json=dict(username=username,password=password),headers=headers)
    def test_budget_commits_on_failure_and_recovers_at_boundary(self):
        for _ in range(5):self.assertEqual(self.attempt().status_code,401)
        blocked=self.attempt(password='DemoAssignment!2026');self.assertEqual(blocked.status_code,429)
        self.assertGreater(int(blocked.headers['retry-after']),0)
        self.now+=timedelta(minutes=15)
        self.assertEqual(self.attempt(password='DemoAssignment!2026').status_code,200)
    def test_success_clears_pair_and_valid_sessions_are_not_rate_limited(self):
        for _ in range(4):self.attempt()
        self.assertEqual(self.attempt(password='DemoAssignment!2026').status_code,200)
        for _ in range(5):self.assertEqual(self.attempt().status_code,401)
        self.assertEqual(self.attempt().status_code,429)
        self.assertEqual(self.client.get('/api/me',headers=self.headers).status_code,200)
    def test_spray_budget_ignores_forwarded_ip_and_hides_identity(self):
        for i in range(30):
            r=self.attempt('unknown-'+str(i),headers={'X-Forwarded-For':'192.0.2.'+str(i)})
            self.assertEqual(r.status_code,401)
        self.assertEqual(self.attempt('smg-col-b',password='DemoAssignment!2026').status_code,429)
        with self.app.state.db.connect() as c:
            raw=json.dumps([dict(r) for r in c.execute('SELECT * FROM login_failures')])
        for secret in ('unknown-','192.0.2.','wrong','DemoAssignment'):self.assertNotIn(secret,raw)
    def test_budget_survives_new_app_and_concurrent_failures(self):
        with ThreadPoolExecutor(max_workers=5) as pool:
            codes=list(pool.map(lambda _:self.attempt().status_code,range(5)))
        self.assertEqual(codes,[401]*5)
        with TestClient(create_app(self.path,lambda:self.now)) as other:
            r=other.post('/api/auth/login',json=dict(username='supervisor',password='DemoAssignment!2026'))
            self.assertEqual(r.status_code,429)
    def test_static_bundle_routes_security_headers_and_no_parent_traversal(self):
        with tempfile.TemporaryDirectory() as td:
            root=Path(td);web=root/'web';web.mkdir();(web/'index.html').write_text('compiled shell')
            (root/'private.txt').write_text('private sentinel')
            with TestClient(create_app(self.path,lambda:self.now,web_path=web)) as c:
                for path,status in [('/',200),('/api/health',200),('/api/me',401),('/missing',404),('/%2e%2e/private.txt',404),('/api/unknown',404)]:
                    r=c.get(path);self.assertEqual(r.status_code,status)
                    self.assertEqual(r.headers['cache-control'],'no-store')
                    self.assertEqual(r.headers['x-content-type-options'],'nosniff')
                    self.assertEqual(r.headers['x-frame-options'],'SAMEORIGIN')
                    self.assertNotIn('private sentinel',r.text)
                self.assertEqual(c.get('/').text,'compiled shell')
                self.assertEqual(c.get('/api/health').json()['version'],'0.13.0')
