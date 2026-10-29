import os,unittest,json
from unittest.mock import patch
from ipaddress import ip_network
from datetime import datetime,timezone
from fastapi.testclient import TestClient
from starlette.requests import Request
from app.main import create_app
from app.deployment import Deployment
from app.security import password_hash
import test_workflows as fixtures

SECRET='Private-owner-test-fixture!2026'
NOW=datetime(2026,10,29,tzinfo=timezone.utc)

class DeploymentTests(unittest.TestCase):
    setUpClass=classmethod(fixtures.WorkflowTests.setUpClass.__func__)
    tearDownClass=classmethod(fixtures.WorkflowTests.tearDownClass.__func__)
    setUp=fixtures.WorkflowTests.setUp
    tearDown=fixtures.WorkflowTests.tearDown
    login=fixtures.WorkflowTests.login
    def test_cloud_environment_fails_closed_without_database_tls_and_owner_secret(self):
        base={'APP_ENV':'cloud','ADMIN_PASSWORD':SECRET,'DATABASE_URL':'postgresql://user:private@db.example/db?sslmode=require'}
        for extra in ({'ADMIN_PASSWORD':''},{'ADMIN_PASSWORD':'DemoAssignment!2026'},{'DATABASE_URL':''},{'DATABASE_URL':'runtime/demo.db'},{'DATABASE_URL':'postgresql://user:private@db.example/db'},{'CORS_ORIGINS':'*'},{'TRUSTED_PROXY_CIDRS':'0.0.0.0/0'}):
            with patch.dict(os.environ,base|extra,clear=True),self.assertRaises(ValueError):Deployment.environment()
        with patch.dict(os.environ,base,clear=True):self.assertTrue(Deployment.environment().cloud)

    def test_proxy_trust_ignores_forged_left_entries_and_untrusted_peers(self):
        d=Deployment(trusted_proxies=(ip_network('10.0.0.0/8'),ip_network('192.0.2.0/24')))
        def req(peer,chain):return Request({'type':'http','client':(peer,123),'headers':[(b'x-forwarded-for',chain.encode())]})
        self.assertEqual(d.peer(req('203.0.113.10','198.51.100.2')),'203.0.113.10')
        self.assertEqual(d.peer(req('10.0.0.3','198.51.100.8, 203.0.113.10, 192.0.2.5')),'203.0.113.10')
        self.assertEqual(d.peer(req('10.0.0.3','invalid,203.0.113.10')),'10.0.0.3')
        self.assertEqual(d.peer(req('10.0.0.3','192.0.2.5')),'10.0.0.3')

    def test_public_viewer_read_scope_forbidden_mutations_and_private_admin(self):
        app=create_app(self.path,lambda:NOW,deployment=Deployment(cloud=True,admin_password=SECRET,cors_origins=()))
        with TestClient(app) as c:
            def login(name,password,status=200):
                r=c.post('/api/auth/login',json={'username':name,'password':password});self.assertEqual(r.status_code,status,r.text)
                return {'Authorization':'Bearer '+r.json()['access_token']} if status==200 else None
            login('supervisor','DemoAssignment!2026',401);login('smg-col-a','DemoAssignment!2026',401)
            owner=login('supervisor',SECRET);viewer=login('demo','DemoAssignment!2026')
            self.assertEqual(c.get('/api/me',headers=viewer).json()['role'],'viewer')
            dashboard=c.get('/api/dashboard',headers=viewer).json();self.assertEqual([v['total'] for v in dashboard['streams'].values()],[72,72])
            self.assertEqual(c.get('/api/cases',headers=viewer).json()['total'],144)
            self.assertEqual(c.get('/api/cases/TAG-0001',headers=viewer).status_code,200)
            for url in ('/api/agents','/api/audit','/api/accounts','/api/models','/api/decisions','/api/analytics/runs','/api/reports'):
                self.assertEqual(c.get(url,headers=viewer).status_code,403,url)
            before=c.get('/api/cases/TAG-0001',headers=owner).json()
            for method,url,body in [('POST','/api/cases',{}),('POST','/api/assignments',{'case_ids':['TAG-0001']}),('POST','/api/cases/TAG-0001/activities',{}),('POST','/api/cases/TAG-0001/integrations',{}),('POST','/api/integrations/process',{}),('PATCH','/api/notifications/missing/read',None)]:
                self.assertEqual(c.request(method,url,headers=viewer,json=body).status_code,403,url)
            self.assertEqual(c.get('/api/cases/TAG-0001',headers=owner).json(),before)
            self.assertEqual(c.post('/api/auth/logout',headers=viewer).status_code,200)
            self.assertEqual(c.get('/api/me',headers=viewer).status_code,401)
            self.assertEqual(c.get('/api/agents',headers=owner).status_code,200)
            with app.state.db.connect() as conn:
                self.assertEqual(conn.execute('SELECT count(*) FROM users').fetchone()[0],14)
                self.assertNotIn(SECRET,json.dumps([dict(x) for x in conn.execute('SELECT * FROM audit')]))

    def test_cloud_secret_rotation_revokes_only_owner_and_keeps_data(self):
        path=self.path
        with TestClient(create_app(path,lambda:NOW,deployment=Deployment(cloud=True,admin_password=SECRET))) as c:
            token=c.post('/api/auth/login',json=dict(username='supervisor',password=SECRET)).json()['access_token']
            viewer=c.post('/api/auth/login',json=dict(username='demo',password='DemoAssignment!2026')).json()['access_token']
        with TestClient(create_app(path,lambda:NOW,deployment=Deployment(cloud=True,admin_password=SECRET+'Changed'))) as c:
            self.assertEqual(c.get('/api/me',headers={'Authorization':'Bearer '+token}).status_code,401)
            self.assertEqual(c.get('/api/cases',headers={'Authorization':'Bearer '+viewer}).json()['total'],144)
            self.assertEqual(c.post('/api/auth/login',json=dict(username='supervisor',password=SECRET+'Changed')).status_code,200)

    def test_viewer_collision_rolls_back_owner_credentials_and_audit(self):
        with self.app.state.db.connect(write=True) as c:
            c.execute('INSERT INTO users VALUES (?,?,?,?,?)',('COLLISION','demo',password_hash('Private-collision-fixture'),'agent',None))
            before=[dict(r) for r in c.execute('SELECT * FROM users ORDER BY id')]
            audits=c.execute('SELECT count(*) FROM audit').fetchone()[0]
        with self.assertRaises(ValueError):
            with TestClient(create_app(self.path,lambda:NOW,deployment=Deployment(cloud=True,admin_password=SECRET))):pass
        with self.app.state.db.connect() as c:
            self.assertEqual([dict(r) for r in c.execute('SELECT * FROM users ORDER BY id')],before)
            self.assertEqual(c.execute('SELECT count(*) FROM audit').fetchone()[0],audits)
