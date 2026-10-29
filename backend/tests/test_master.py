import json
import shutil
import sqlite3
import tempfile
import unittest
from concurrent.futures import ThreadPoolExecutor
from contextlib import closing
from datetime import datetime, timedelta, timezone
from pathlib import Path
from uuid import uuid4

from fastapi.testclient import TestClient

from app.db import Database
from app.main import create_app
from app.seed import DEMO_PASSWORD
from test_imports import xlsx


class MasterTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory()
        cls.base = Path(cls.temp.name) / 'base.db'
        with TestClient(create_app(str(cls.base))): pass

    @classmethod
    def tearDownClass(cls): cls.temp.cleanup()

    def setUp(self):
        self.path = Path(self.temp.name) / f'{uuid4().hex}.db'
        shutil.copy2(self.base, self.path)
        self.now = datetime(2026, 10, 28, 2, tzinfo=timezone.utc)
        self.app = create_app(str(self.path), lambda: self.now)
        self.client = TestClient(self.app).__enter__()
        self.h = self.login('supervisor')

    def tearDown(self): self.client.__exit__(None, None, None)

    def login(self, username):
        r = self.client.post('/api/auth/login', json=dict(username=username, password=DEMO_PASSWORD))
        self.assertEqual(r.status_code, 200, r.text)
        return {'Authorization': 'Bearer '+r.json()['access_token']}

    def call(self, method, path, data=None, status=200, headers=None):
        r = self.client.request(method, path, json=data, headers=headers or self.h)
        self.assertEqual(r.status_code, status, r.text)
        return r.json()

    def agent(self, aid='SMG-S6-A', **changes):
        p = dict(id=aid, name='Petugas Sintetis S6', region_id='SMG', kind='collection', team='A', channel='Tele',
                 approach='Negosiasi', capacity=12, active=True, username=aid.lower(), password=DEMO_PASSWORD)
        p.update(changes)
        return self.call('POST', '/api/master/agents', p, 201)

    def case(self, **changes):
        p = dict(kind='collection', customer='UAT S6 Sintetis', region_id='SMG', difficulty='Low', amount=100000)
        p.update(changes)
        return self.call('POST', '/api/cases', p, 201)['id']

    def detail(self, cid): return self.call('GET', '/api/cases/'+cid)

    def override(self, cid, aid, status=200, **changes):
        p = dict(agent_id=aid, reason='Alokasi spesifik untuk pengujian', expected_version=self.detail(cid)['case']['version'], request_key=uuid4().hex)
        p.update(changes)
        return self.call('POST', f'/api/cases/{cid}/override-assignment', p, status), p

    def activity(self, cid, code, **changes):
        return self.call('POST', f'/api/cases/{cid}/activities', dict(code=code, expected_version=self.detail(cid)['case']['version'], request_key=uuid4().hex, **changes))

    def edit_agent(self, aid, status=200, **changes):
        row = next(a for a in self.call('GET', '/api/agents') if a['id'] == aid)
        p = {k: row[k] for k in ['name','region_id','kind','team','channel','approach','capacity']}
        p.update(active=bool(row['active']), expected_version=row['version'], reason='Perubahan profil untuk pengujian')
        p.update(changes)
        return self.call('PATCH', '/api/master/agents/'+aid, p, status)

    def test_region_lifecycle_uniqueness_scope_and_inactive_integration(self):
        r = self.call('POST', '/api/master/regions', dict(id='YOG', name='Yogyakarta', active=True), 201)
        self.call('POST', '/api/master/regions', dict(id='YOG', name='Yogyakarta'), 409)
        self.call('POST', '/api/master/regions', dict(id='JOG', name='yogyakarta'), 409)
        self.call('POST', '/api/master/regions', dict(id='JOG', name='SMG'), 409)
        p = dict(name='Yogyakarta Demo', active=False, expected_version=r['version'], reason='Wilayah uji dinonaktifkan')
        self.call('PATCH', '/api/master/regions/YOG', p)
        self.call('PATCH', '/api/master/regions/YOG', p, 409)
        config = self.call('GET', '/api/config')
        self.assertNotIn('YOG', [r['id'] for r in config['regions']])
        self.assertIn('YOG', [r['id'] for r in config['report_regions']])
        self.call('POST', '/api/cases', dict(kind='collection', region_id='YOG', customer='Sintetis', amount=1000), 422)
        self.agent(region_id='YOG', active=False)
        self.edit_agent('SMG-S6-A', status=409, active=True)
        self.call('PATCH', '/api/master/regions/SMG', dict(name='Semarang', active=False, expected_version=1, reason='Coba menonaktifkan wilayah'), 409)

    def test_agent_account_atomic_unique_password_and_deactivation_keeps_old_login(self):
        a = self.agent()
        self.call('POST', '/api/master/agents', dict(id='SECOND', name='Petugas Kedua', region_id='SMG', kind='collection', team='A', channel='Tele', approach='Tele', capacity=12, username='smg-s6-a', password=DEMO_PASSWORD), 409)
        self.assertFalse(any(a['id']=='SECOND' for a in self.call('GET','/api/agents')))
        h = self.login('smg-s6-a')
        cid = self.case(); self.override(cid, a['id'])
        self.edit_agent(a['id'], active=False)
        self.call('GET', '/api/cases/'+cid, headers=h)
        self.login('smg-s6-a')
        other = self.case(); self.override(other, a['id'], 409)
        with self.app.state.db.connect() as db:
            self.assertNotIn(DEMO_PASSWORD, '\n'.join(r[0] for r in db.execute('SELECT detail FROM audit')))
            self.assertNotEqual(db.execute("SELECT password_hash FROM users WHERE username='smg-s6-a'").fetchone()[0], DEMO_PASSWORD)

    def test_active_work_blocks_routing_change_capacity_and_stale_profile(self):
        a = self.agent(); cid = self.case(); self.override(cid, a['id'])
        self.edit_agent(a['id'], status=409, region_id='BDG')
        self.edit_agent(a['id'], status=409, kind='origination')
        self.edit_agent(a['id'], status=409, team='B')
        self.edit_agent(a['id'], name='Nama baru sintetis')
        self.call('PATCH','/api/agents/'+a['id'],dict(capacity=12,active=True,expected_version=1),409)
        self.override(self.case(), a['id'])
        self.edit_agent(a['id'], status=409, capacity=1)
        self.assertEqual(self.detail(cid)['assignments'][0]['agent_name'], 'Petugas Sintetis S6')

    def test_profile_move_after_completion_preserves_historical_reports_and_selectors(self):
        a = self.agent(); cid = self.case(); self.override(cid,a['id']); self.activity(cid,'payment',amount=100000)
        self.edit_agent(a['id'], name='Petugas Pengajuan Bandung', region_id='BDG',kind='origination',team='B',channel='Lapangan')
        for view in ['cases','cycles']:
            report = self.call('GET',f'/api/reports?kind=collection&view={view}&region_id=SMG&agent_id={a["id"]}')
            self.assertEqual(report['total'],1)
            if view=='cycles':
                self.assertEqual(report['items'][0]['team'],'A')
                self.assertEqual(report['items'][0]['agent_name'],'Petugas Sintetis S6')
        row = next(r for r in self.call('GET','/api/agents') if r['id']==a['id'])
        self.assertIn(dict(kind='collection',region_id='SMG'),row['report_scopes'])
        self.assertIn(dict(kind='origination',region_id='BDG'),row['report_scopes'])

    def test_override_hard_rules_version_and_payload_idempotency(self):
        a = self.agent(); cid = self.case()
        for aid in ['SMG-col-B','BDG-col-A','SMG-ori-A','missing']:
            self.override(cid,aid,409)
        self.override(cid,a['id'],409,expected_version=999)
        first,p = self.override(cid,a['id'])
        replay = self.call('POST',f'/api/cases/{cid}/override-assignment',p)
        self.assertTrue(replay['replayed']); self.assertEqual(first['cycle'],replay['cycle'])
        self.call('POST',f'/api/cases/{cid}/override-assignment',{**p,'reason':'Alasan berubah tidak boleh'},409)
        self.override(cid,a['id'],409)
        with self.app.state.db.connect() as db:
            self.assertEqual(db.execute("SELECT count(*) FROM audit WHERE action='override_assignment'").fetchone()[0],1)

    def test_override_reassign_projection_payment_history_and_scope_transfer(self):
        a = self.agent(team='B', channel='Lapangan')
        cid = self.case(difficulty='Medium',dpd=15)  # 67.5 -> 55.5 after unreachable
        self.override(cid,'SMG-col-A'); self.activity(cid,'unreachable'); self.activity(cid,'payment',amount=20000)
        original=self.detail(cid)
        options=self.call('GET',f'/api/cases/{cid}/assignment-options')
        self.assertEqual(options['target_team'],'B'); self.assertEqual(options['score'],55.5)
        self.assertEqual(self.detail(cid)['case']['score'],67.5)
        self.override(cid,'SMG-col-A',409)
        self.override(cid,a['id'])
        fresh=self.detail(cid)
        self.assertEqual(fresh['case']['paid'],20000); self.assertEqual(fresh['case']['score'],55.5)
        self.assertEqual(fresh['assignments'][0]['outcome'],'superseded')
        self.assertEqual(fresh['assignments'][0]['score'],67.5)
        self.assertEqual(len(fresh['activities']),2)
        old_user=self.login('smg-col-a'); new_user=self.login('smg-s6-a')
        self.call('GET',f'/api/cases/{cid}',status=404,headers=old_user)
        self.call('GET',f'/api/cases/{cid}',headers=new_user)
        self.assertEqual(original['case']['cycle'],1); self.assertEqual(fresh['case']['cycle'],2)

    def test_concurrent_override_capacity_and_retries_are_atomic(self):
        a=self.agent(capacity=1); cids=[self.case(),self.case()]
        payloads=[dict(agent_id=a['id'],expected_version=1,reason='Concurrent kapasitas pengujian',request_key=uuid4().hex) for _ in cids]
        def write(i): return self.client.post(f'/api/cases/{cids[i]}/override-assignment',json=payloads[i],headers=self.h)
        with ThreadPoolExecutor(2) as pool: results=list(pool.map(write,[0,1]))
        self.assertEqual(sorted(r.status_code for r in results),[200,409])
        winner=next(i for i,r in enumerate(results) if r.status_code==200)
        with ThreadPoolExecutor(2) as pool: retry=list(pool.map(write,[winner,winner]))
        self.assertTrue(all(r.status_code==200 and r.json()['replayed'] for r in retry))
        with self.app.state.db.connect() as db:
            self.assertEqual(db.execute('SELECT count(*) FROM assignments WHERE agent_id=?',(a['id'],)).fetchone()[0],1)
            self.assertEqual(db.execute('SELECT count(*) FROM assignment_overrides').fetchone()[0],1)
        self.assertEqual(self.detail(cids[1-winner])['case']['cycle'],0)

    def test_origination_override_preserves_qualification_terminal_and_late_outcome(self):
        a=self.agent(kind='origination')
        cid=self.case(kind='origination',income=5000000,interest=4)
        self.override(cid,'SMG-ori-A'); self.activity(cid,'documents'); self.activity(cid,'qualified')
        self.now+=timedelta(hours=73)
        self.h=self.login('supervisor')
        self.override(cid,a['id'])
        d=self.detail(cid)
        self.assertEqual(d['case']['status'],'qualified'); self.assertEqual(d['assignments'][0]['outcome'],'no_success')
        self.activity(cid,'disburse',amount=100000)
        self.override(cid,'SMG-ori-A',409)

    def test_role_validation_audit_and_restart_migration(self):
        h=self.login('smg-col-a');cid=self.case()
        for path in ['/api/master/regions','/api/master/audit',f'/api/cases/{cid}/assignment-options']:
            self.call('GET',path,status=403,headers=h)
        self.call('POST','/api/master/regions',dict(id='YOG',name='Yogyakarta'),403,headers=h)
        self.call('POST',f'/api/cases/{cid}/override-assignment',dict(expected_version=1,reason='Alokasi pengujian',agent_id='SMG-col-A',request_key=uuid4().hex),403,headers=h)
        self.call('POST','/api/master/regions',dict(id='bad',name='Bad'),422)
        self.agent();self.override(cid,'SMG-S6-A')
        events=self.call('GET','/api/master/audit')
        self.assertEqual([a['action'] for a in events],['override_assignment','create_agent'])
        before=self.detail(cid)
        Database(str(self.path)).initialize();Database(str(self.path)).initialize()
        with TestClient(create_app(str(self.path),lambda:self.now)) as second:
            self.assertEqual(second.get('/api/cases/'+cid,headers=self.h).json(),before)
        # Real v2-style database with existing assignment and only the old columns.
        legacy=Path(self.temp.name)/f'{uuid4().hex}-legacy.db'
        with closing(sqlite3.connect(self.path)) as source, closing(sqlite3.connect(legacy)) as copy: source.backup(copy)
        with closing(sqlite3.connect(legacy)) as db:
            for table,cols in {'regions':['active','version'],'agents':['version'],'assignments':['agent_name','agent_team','agent_channel']}.items():
                for col in cols: db.execute(f'ALTER TABLE {table} DROP COLUMN {col}')
            db.execute('PRAGMA user_version=2')
            db.commit()
        Database(str(legacy)).initialize()
        with closing(sqlite3.connect(legacy)) as db:
            self.assertEqual(db.execute('PRAGMA user_version').fetchone()[0],3)
            self.assertEqual(db.execute('SELECT agent_team FROM assignments').fetchone()[0],'A')
            self.assertEqual(db.execute('SELECT count(*) FROM cases').fetchone()[0],145)

    def test_region_change_invalidates_import_and_concurrent_activation_is_consistent(self):
        self.call('POST','/api/master/regions',dict(id='YOG',name='Yogyakarta'),201)
        r=self.client.post('/api/imports/upload?kind=collection&filename=regions.xlsx',content=xlsx(rows=[['REG-S6','Sintetis','YOG','Low',1000,0]]),headers=self.h)
        self.assertEqual(r.status_code,201,r.text);bid=r.json()['id']
        preview=self.call('POST',f'/api/imports/{bid}/preview',dict(sheet='Data',header_row=1,mapping=dict(source_ref=1,customer=2,region_id=3,difficulty=4,amount=5,dpd=6)))
        self.assertTrue(preview['preview']['can_commit'])
        self.call('PATCH','/api/master/regions/YOG',dict(name='Yogyakarta',active=False,expected_version=1,reason='Nonaktifkan sebelum commit'))
        self.call('POST',f'/api/imports/{bid}/commit',dict(expected_revision=preview['revision'],acknowledge_ignored=False),409)
        again=self.call('POST',f'/api/imports/{bid}/preview',dict(sheet='Data',header_row=1,mapping=dict(source_ref=1,customer=2,region_id=3,difficulty=4,amount=5,dpd=6)))
        self.assertFalse(again['preview']['can_commit'])
        # Either disable wins and activation fails, or activation wins and disable fails.
        a=self.agent(region_id='YOG',active=False)
        self.call('PATCH','/api/master/regions/YOG',dict(name='Yogyakarta',active=True,expected_version=2,reason='Aktifkan kembali untuk uji'))
        def disable(): return self.client.patch('/api/master/regions/YOG',json=dict(name='Yogyakarta',active=False,expected_version=3,reason='Uji concurrent wilayah'),headers=self.h)
        def activate(): return self.client.patch('/api/agents/'+a['id'],json=dict(capacity=12,active=True),headers=self.h)
        with ThreadPoolExecutor(2) as pool: results=[f.result() for f in [pool.submit(disable),pool.submit(activate)]]
        self.assertEqual(sorted(r.status_code for r in results),[200,409])
        with self.app.state.db.connect() as db:
            self.assertFalse(db.execute('SELECT 1 FROM agents a JOIN regions r ON r.id=a.region_id WHERE a.active=1 AND r.active=0').fetchone())
            self.assertFalse(db.execute('SELECT 1 FROM import_case_refs').fetchone())
