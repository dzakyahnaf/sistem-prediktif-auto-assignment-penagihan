import shutil
import tempfile
import unittest
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
from pathlib import Path
from uuid import uuid4

from fastapi.testclient import TestClient

from app.domain import score_case, target_team
from app.main import create_app
from app.seed import DEMO_PASSWORD


class WorkflowTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory()
        cls.base = str(Path(cls.temp.name) / 'base.db')
        with TestClient(create_app(cls.base)) as client:
            assert client.get('/api/health').status_code == 200

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def setUp(self):
        self.now = datetime(2026, 10, 27, 2, tzinfo=timezone.utc)
        self.path = str(Path(self.temp.name) / f'{uuid4().hex}.db')
        shutil.copy2(self.base, self.path)
        self.app = create_app(self.path, lambda: self.now)
        self.client = TestClient(self.app).__enter__()
        self.headers = self.login('supervisor')

    def tearDown(self):
        self.client.__exit__(None, None, None)

    def login(self, username):
        r = self.client.post('/api/auth/login', json=dict(username=username, password=DEMO_PASSWORD))
        self.assertEqual(r.status_code, 200, r.text)
        return {'Authorization': 'Bearer '+r.json()['access_token']}

    def get_case(self, cid):
        return self.client.get('/api/cases/'+cid, headers=self.headers).json()['case']

    def create(self, kind='collection', difficulty='Low', **kw):
        data = dict(kind=kind, customer='Pemohon Uji', region_id='SMG', difficulty=difficulty, amount=1_000_000)
        if kind == 'origination':
            data.update(income=5_000_000, interest=4)
        data.update(kw)
        r = self.client.post('/api/cases', json=data, headers=self.headers)
        self.assertEqual(r.status_code, 201, r.text)
        return r.json()['id']

    def assign(self, ids):
        return self.client.post('/api/assignments', json={'case_ids': ids}, headers=self.headers)

    def activity(self, cid, code, **kw):
        payload = dict(code=code, expected_version=self.get_case(cid)['version'], request_key=uuid4().hex, **kw)
        return self.client.post(f'/api/cases/{cid}/activities', json=payload, headers=self.headers)

    def test_seed_idempotent_and_separate_streams(self):
        from app.seed import seed_demo
        seed_demo(self.app.state.db)
        data = self.client.get('/api/dashboard', headers=self.headers).json()
        self.assertEqual([v['total'] for v in data['streams'].values()], [72, 72])
        self.assertEqual(len(self.client.get('/api/agents', headers=self.headers).json()), 12)

    def test_pagination_beyond_200_with_stable_order_and_combined_filters(self):
        ids = [self.create(customer=f'Pagination Demo {i:03}') for i in range(210)]
        self.create('origination', customer='Pagination Demo Pengajuan')
        seen = []
        for offset in range(0, 225, 25):
            result = self.client.get('/api/cases', params=dict(kind='collection', q='Pagination Demo', offset=offset, limit=25), headers=self.headers).json()
            self.assertEqual((result['total'], result['offset'], result['limit']), (210, offset, 25))
            seen.extend(row['id'] for row in result['items'])
        self.assertEqual(seen, sorted(ids))  # Equal scores use ID as a stable tiebreaker.
        self.assertEqual(len(set(seen)), 210)
        found = self.client.get('/api/cases', params=dict(q=sorted(ids)[-1], kind='collection'), headers=self.headers).json()
        self.assertEqual([r['id'] for r in found['items']], [sorted(ids)[-1]])
        self.assign(ids[:2])
        filtered = self.client.get('/api/cases', params=dict(q='Pagination Demo', kind='collection', status='assigned', limit=1), headers=self.headers).json()
        self.assertEqual((filtered['total'], len(filtered['items'])), (2, 1))
        empty = self.client.get('/api/cases', params=dict(q='Pagination Demo', kind='collection', offset=999), headers=self.headers).json()
        self.assertEqual((empty['total'], empty['items']), (210, []))

    def test_server_search_region_literals_and_agent_scope(self):
        mine = self.create(customer='Literal 100%_\\Demo')
        other = self.create(customer='Literal 100xxDemo', region_id='SBY')
        self.assign([mine, other])
        for term in ['%', '_', '\\']:
            result = self.client.get('/api/cases', params=dict(q=term), headers=self.headers).json()
            self.assertEqual([r['id'] for r in result['items']], [mine])
        result = self.client.get('/api/cases', params=dict(q='  smg  ', kind='collection', limit=200), headers=self.headers).json()
        self.assertTrue(result['total'] > 1)
        self.assertTrue(all(r['region_id'] == 'SMG' for r in result['items']))
        agent = self.login('smg-col-a')
        scoped = self.client.get('/api/cases', params=dict(q='smg', status='assigned', limit=1), headers=agent).json()
        self.assertEqual((scoped['total'], [r['id'] for r in scoped['items']]), (1, [mine]))
        hidden = self.client.get('/api/cases', params=dict(q=other), headers=agent).json()
        self.assertEqual((hidden['total'], hidden['items']), (0, []))

    def test_auth_and_logout(self):
        self.assertEqual(self.client.get('/api/cases').status_code, 401)
        self.assertEqual(self.client.post('/api/auth/login', json={'username':'supervisor','password':'wrong'}).status_code, 401)
        self.assertEqual(self.client.post('/api/auth/logout', headers=self.headers).status_code, 200)
        self.assertEqual(self.client.get('/api/me', headers=self.headers).status_code, 401)

    def test_expired_sessions(self):
        self.now += timedelta(hours=8)
        self.assertEqual(self.client.get('/api/me', headers=self.headers).status_code, 401)

    def test_low_high_override_score_and_medium_boundary(self):
        for difficulty, score, expected in [('Low',5,'A'),('High',95,'B'),('Medium',60,'A'),('Medium',59.9,'B')]:
            self.assertEqual(target_team(dict(difficulty=difficulty,score=score)), expected)

    def test_assignment_filters_region_domain_team_and_is_idempotent(self):
        cid = self.create('origination', difficulty='High', region_id='BDG')
        self.assertEqual(self.assign([cid]).json()['results'][0]['agent_id'], 'BDG-ori-B')
        self.assertFalse(self.assign([cid]).json()['results'][0]['assigned'])
        self.assertEqual(self.get_case(cid)['cycle'], 1)

    def test_capacity_concurrent_and_inactive(self):
        aid = 'SMG-col-A'
        self.client.patch('/api/agents/'+aid, json=dict(capacity=1, active=True), headers=self.headers)
        ids = [self.create() for _ in range(5)]
        with ThreadPoolExecutor(max_workers=5) as pool:
            results = list(pool.map(lambda cid:self.assign([cid]).json()['results'][0], ids))
        self.assertEqual(sum(r['assigned'] for r in results), 1)
        self.client.patch('/api/agents/'+aid, json=dict(capacity=1, active=False), headers=self.headers)
        self.assertFalse(self.assign([self.create()]).json()['results'][0]['assigned'])

    def test_supervisor_agent_settings_preserve_workload_and_audit(self):
        aid = 'SMG-col-A'
        first, second = self.create(), self.create()
        self.assign([first, second])
        self.activity(first, 'payment', amount=1_000_000)
        url = '/api/agents/' + aid
        self.assertEqual(self.client.patch(url, json=dict(capacity=1, active=False), headers=self.headers).status_code, 409)
        before = self.client.get('/api/agents', headers=self.headers).json()
        self.assertEqual(next(a for a in before if a['id'] == aid)['active'], 1)
        self.assertEqual(self.client.patch(url, json=dict(capacity=14, active=False), headers=self.headers).status_code, 200)
        agent_headers = self.login('smg-col-a')
        self.assertEqual(self.client.patch(url, json=dict(capacity=20, active=True), headers=agent_headers).status_code, 403)
        current = self.get_case(second)
        activity = dict(code='contacted', expected_version=current['version'], request_key=uuid4().hex)
        self.assertEqual(self.client.post(f'/api/cases/{second}/activities', json=activity, headers=agent_headers).status_code, 200)
        self.assertFalse(self.assign([self.create()]).json()['results'][0]['assigned'])
        with TestClient(create_app(self.path, lambda: self.now)) as restarted:
            agents = restarted.get('/api/agents', headers=self.headers).json()
            settings = next(a for a in agents if a['id'] == aid)
            self.assertEqual((settings['capacity'], settings['active'], settings['daily_load'], settings['active_load']), (14, 0, 2, 1))
            entries = restarted.get('/api/audit', headers=self.headers).json()
            changes = [a for a in entries if a['action'] == 'update_agent']
            self.assertEqual(len(changes), 1)
            self.assertIn('"capacity": 14', changes[0]['detail'])
            self.assertIn('"active": false', changes[0]['detail'])

    def test_agent_scope_and_privileges(self):
        mine, other = self.create(), self.create(region_id='SBY')
        self.assign([mine,other])
        agent_headers = self.login('smg-col-a')
        result = self.client.get('/api/cases', headers=agent_headers).json()
        self.assertEqual([r['id'] for r in result['items']], [mine])
        self.assertEqual(self.client.get('/api/cases/'+other, headers=agent_headers).status_code, 404)
        self.assertEqual(self.client.post('/api/assignments', json={'case_ids':[mine]}, headers=agent_headers).status_code,403)
        self.assertEqual(self.client.get('/api/agents', headers=agent_headers).status_code,403)
        self.assertEqual(self.client.get('/api/reports/export?kind=collection', headers=agent_headers).status_code,403)

    def test_partial_payment_and_idempotent_retry(self):
        cid = self.create(); self.assign([cid])
        payload = dict(code='payment',amount=400000,expected_version=self.get_case(cid)['version'],request_key=uuid4().hex)
        first = self.client.post(f'/api/cases/{cid}/activities',json=payload,headers=self.headers)
        retry = self.client.post(f'/api/cases/{cid}/activities',json=payload,headers=self.headers)
        self.assertEqual(first.status_code,200)
        self.assertTrue(retry.json()['replayed'])
        self.assertEqual(self.get_case(cid)['paid'],400000)
        self.assertEqual(self.get_case(cid)['status'],'in_progress')
        payload['amount'] = 500000
        self.assertEqual(self.client.post(f'/api/cases/{cid}/activities',json=payload,headers=self.headers).status_code,409)
        self.assertEqual(self.activity(cid,'payment',amount=600000).status_code,200)
        detail = self.client.get('/api/cases/'+cid,headers=self.headers).json()
        self.assertEqual(detail['assignments'][0]['outcome'],'success')

    def test_success_at_exact_72_hours_and_late_payment(self):
        a,b = self.create(),self.create(); self.assign([a,b])
        self.now += timedelta(hours=72)
        self.headers = self.login('supervisor')
        self.activity(a,'payment',amount=1000000)
        self.now += timedelta(seconds=1)
        self.activity(b,'payment',amount=1000000)
        for cid, expected in [(a,'success'),(b,'no_success')]:
            d=self.client.get('/api/cases/'+cid,headers=self.headers).json()
            self.assertEqual(d['case']['status'],'paid')
            self.assertEqual(d['assignments'][0]['outcome'],expected)

    def test_optimistic_lock_prevents_lost_updates(self):
        cid=self.create(); self.assign([cid]); old=self.get_case(cid)['version']
        self.activity(cid,'contacted')
        payload=dict(code='payment',amount=1,expected_version=old,request_key=uuid4().hex)
        self.assertEqual(self.client.post(f'/api/cases/{cid}/activities',json=payload,headers=self.headers).status_code,409)
        self.assertEqual(self.get_case(cid)['paid'],0)

    def test_reassignment_uses_only_completed_cycle_feedback(self):
        cid=self.create(); self.assign([cid]); before=self.get_case(cid)['score']
        self.activity(cid,'unreachable')
        self.assertEqual(self.get_case(cid)['score'],before)
        r=self.client.post(f'/api/cases/{cid}/reassign',json=dict(expected_version=self.get_case(cid)['version'],reason='Evaluasi setelah tidak terhubung'),headers=self.headers)
        self.assertEqual(r.status_code,200,r.text)
        self.assertEqual(self.get_case(cid)['score'],before-12)
        self.assertEqual(self.get_case(cid)['cycle'],2)

    def test_reassignment_without_capacity_rolls_back(self):
        cid=self.create(); self.assign([cid])
        self.client.patch('/api/agents/SMG-col-A',json=dict(capacity=1,active=True),headers=self.headers)
        case=self.get_case(cid)
        r=self.client.post(f'/api/cases/{cid}/reassign',json=dict(expected_version=case['version'],reason='Pindah petugas untuk tindak lanjut'),headers=self.headers)
        self.assertEqual(r.status_code,409)
        detail=self.client.get('/api/cases/'+cid,headers=self.headers).json()
        self.assertEqual(detail['case'],case)
        self.assertIsNone(detail['assignments'][0]['ended_at'])

    def test_origination_full_workflow_and_wrong_domain(self):
        cid=self.create('origination'); self.assign([cid])
        self.assertEqual(self.activity(cid,'payment',amount=1000).status_code,422)
        self.assertEqual(self.activity(cid,'disburse',amount=1000000).status_code,409)
        self.assertEqual(self.activity(cid,'qualified').status_code,409)
        self.assertEqual(self.activity(cid,'documents').status_code,200)
        self.assertEqual(self.activity(cid,'qualified').status_code,200)
        self.assertEqual(self.activity(cid,'disburse',amount=999).status_code,422)
        self.assertEqual(self.activity(cid,'disburse',amount=1000000).status_code,200)
        self.assertEqual(self.get_case(cid)['status'],'disbursed')
        self.assertEqual(self.activity(cid,'contacted').status_code,409)

    def test_origination_rejection_requires_reason(self):
        cid=self.create('origination'); self.assign([cid])
        self.assertEqual(self.activity(cid,'reject').status_code,422)
        self.assertEqual(self.activity(cid,'reject',note='Pemohon membatalkan permohonan demo').status_code,200)
        self.assertEqual(self.get_case(cid)['status'],'rejected')

    def test_validation_and_overpayment(self):
        cid=self.create(); self.assign([cid])
        self.assertEqual(self.activity(cid,'payment',amount=1000001).status_code,422)
        self.assertEqual(self.activity(cid,'promise',promise_date='2020-01-01').status_code,422)
        self.assertEqual(self.activity(cid,'contacted',amount=1).status_code,422)
        self.assertEqual(self.assign([cid,cid]).status_code,422)
        self.assertEqual(self.client.post('/api/cases',json=dict(kind='origination',customer='Test',region_id='SMG',amount=1000),headers=self.headers).status_code,422)

    def test_atomic_batch_with_invalid_id(self):
        cid=self.create()
        self.assertEqual(self.assign([cid,'MISSING']).status_code,404)
        self.assertIsNone(self.get_case(cid)['agent_id'])

    def test_export_formula_escaping_and_audit(self):
        self.create(customer='=1+1')
        r=self.client.get('/api/reports/export?kind=collection',headers=self.headers)
        self.assertEqual(r.status_code,200)
        self.assertIn("'=1+1",r.text)
        self.assertGreater(len(self.client.get('/api/audit',headers=self.headers).json()),0)

    def test_new_score_is_independent_of_current_outcome(self):
        case=dict(kind='collection',difficulty='Medium',dpd=15)
        first=score_case(case)
        case.update(paid=1000000,status='paid',agent_id='ANY')
        self.assertEqual(score_case(case),first)

    def test_daily_limit_does_not_reset_on_completion(self):
        aid='SMG-col-A'
        self.client.patch('/api/agents/'+aid,json=dict(capacity=1,active=True),headers=self.headers)
        a,b=self.create(),self.create()
        self.assign([a]); self.activity(a,'payment',amount=1000000)
        self.assertFalse(self.assign([b]).json()['results'][0]['assigned'])
        # 17:00 UTC is midnight WIB, which starts a new capacity day.
        self.now=self.now.replace(hour=17)
        self.headers=self.login('supervisor')
        self.assertTrue(self.assign([b]).json()['results'][0]['assigned'])

    def test_active_load_survives_day_boundary(self):
        self.client.patch('/api/agents/SMG-col-A',json=dict(capacity=1,active=True),headers=self.headers)
        a,b=self.create(),self.create(); self.assign([a])
        self.now+=timedelta(days=1); self.headers=self.login('supervisor')
        self.assertFalse(self.assign([b]).json()['results'][0]['assigned'])

    def test_concurrent_payment_retries_are_exactly_once(self):
        cid=self.create(); self.assign([cid])
        payload=dict(code='payment',amount=400000,expected_version=self.get_case(cid)['version'],request_key=uuid4().hex)
        with ThreadPoolExecutor(max_workers=4) as pool:
            results=list(pool.map(lambda _:self.client.post(f'/api/cases/{cid}/activities',json=payload,headers=self.headers),range(4)))
        self.assertTrue(all(r.status_code==200 for r in results))
        detail=self.client.get('/api/cases/'+cid,headers=self.headers).json()
        self.assertEqual(detail['case']['paid'],400000)
        self.assertEqual(len(detail['activities']),1)

    def test_data_persists_on_restart(self):
        cid=self.create('origination'); self.assign([cid]); self.activity(cid,'documents')
        with TestClient(create_app(self.path,lambda:self.now)) as restarted:
            data=restarted.get('/api/cases/'+cid,headers=self.headers).json()
            self.assertEqual(data['case']['status'],'documents')
            self.assertEqual(len(data['activities']),1)

    def test_cors_and_openapi_contract(self):
        r=self.client.options('/api/cases',headers={'Origin':'http://127.0.0.1:5173','Access-Control-Request-Method':'GET','Access-Control-Request-Headers':'authorization'})
        self.assertEqual(r.headers['access-control-allow-origin'],'http://127.0.0.1:5173')
        self.assertIn('/api/cases/{case_id}/activities',self.client.get('/openapi.json').json()['paths'])

    def test_expired_token_blocks_all_screen_and_mutation_endpoints(self):
        cid=self.create(); self.assign([cid])
        case=self.get_case(cid)
        with self.app.state.db.connect() as conn:
            before=[conn.execute(f'SELECT COUNT(*) FROM {table}').fetchone()[0] for table in ['cases','assignments','activities','audit']]
        self.now+=timedelta(hours=8)
        endpoints=[
            ('GET','/api/me',None),('GET','/api/config',None),('GET','/api/dashboard',None),
            ('GET','/api/cases',None),('GET',f'/api/cases/{cid}',None),('GET','/api/agents',None),
            ('GET','/api/audit',None),('GET','/api/reports/export?kind=collection',None),
            ('POST','/api/cases',dict(kind='collection',customer='Expired demo',region_id='SMG',amount=1000000)),
            ('POST','/api/assignments',dict(case_ids=[cid])),
            ('POST',f'/api/cases/{cid}/reassign',dict(expected_version=case['version'],reason='Token yang sudah kedaluwarsa')),
            ('POST',f'/api/cases/{cid}/activities',dict(expected_version=case['version'],request_key=uuid4().hex,code='payment',amount=1000000)),
            ('PATCH','/api/agents/SMG-col-A',dict(capacity=15,active=False)),
        ]
        for method,path,payload in endpoints:
            with self.subTest(method=method,path=path):
                response=self.client.request(method,path,json=payload,headers=self.headers)
                self.assertEqual(response.status_code,401,response.text)
                self.assertEqual(response.headers['www-authenticate'],'Bearer')
                self.assertEqual(response.headers['cache-control'],'no-store')
        with self.app.state.db.connect() as conn:
            after=[conn.execute(f'SELECT COUNT(*) FROM {table}').fetchone()[0] for table in ['cases','assignments','activities','audit']]
        self.assertEqual(before,after)

    def test_logout_old_token_does_not_revoke_new_session(self):
        old=self.headers
        new=self.login('supervisor')
        self.assertEqual(self.client.post('/api/auth/logout',headers=old).status_code,200)
        self.assertEqual(self.client.get('/api/me',headers=old).status_code,401)
        self.assertEqual(self.client.get('/api/me',headers=new).status_code,200)

    def test_auth_and_private_responses_are_not_cached(self):
        for response in [
            self.client.get('/api/dashboard',headers=self.headers),
            self.client.get('/api/cases?limit=0',headers=self.headers),
            self.client.get('/api/me'),
            self.client.post('/api/auth/login',json={'username':'wrong','password':'wrong'}),
            self.client.post('/api/auth/login',json={'username':'supervisor','password':DEMO_PASSWORD}),
        ]:
            self.assertEqual(response.headers['cache-control'],'no-store')

    def test_expiry_then_agent_login_cannot_read_supervisor_scope(self):
        mine,other=self.create(),self.create(region_id='SBY')
        self.assign([mine,other])
        expired=self.headers
        self.now+=timedelta(hours=8)
        agent=self.login('smg-col-a')
        self.assertEqual(self.client.get('/api/cases',headers=expired).status_code,401)
        rows=self.client.get('/api/cases',headers=agent).json()['items']
        self.assertEqual([r['id'] for r in rows],[mine])
        self.assertEqual(self.client.get('/api/cases/'+other,headers=agent).status_code,404)


if __name__ == '__main__':
    unittest.main()
