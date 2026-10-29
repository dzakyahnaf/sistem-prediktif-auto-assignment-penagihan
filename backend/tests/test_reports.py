import csv
import io
import json
import shutil
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path
from uuid import uuid4

from fastapi.testclient import TestClient
from app.main import create_app
from app.seed import DEMO_PASSWORD


class ReportTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory()
        cls.base = str(Path(cls.temp.name) / 'base.db')
        with TestClient(create_app(cls.base)):
            pass

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def setUp(self):
        self.now = datetime(2026, 10, 27, 17, tzinfo=timezone.utc)  # 28 October 00:00 WIB
        self.path = str(Path(self.temp.name) / f'{uuid4().hex}.db')
        shutil.copy2(self.base, self.path)
        self.app = create_app(self.path, lambda: self.now)
        self.client = TestClient(self.app).__enter__()
        self.headers = self.login('supervisor')

    def tearDown(self):
        self.client.__exit__(None, None, None)

    def login(self, username):
        r = self.client.post('/api/auth/login', json=dict(username=username, password=DEMO_PASSWORD))
        r.raise_for_status()
        return {'Authorization': 'Bearer ' + r.json()['access_token']}

    def create(self, kind='collection', name='Laporan Uji', **overrides):
        payload = dict(kind=kind, customer=name, region_id='SMG', difficulty='Low', amount=1000000)
        if kind == 'origination':
            payload.update(income=5000000, interest=4)
        payload.update(overrides)
        r = self.client.post('/api/cases', json=payload, headers=self.headers)
        r.raise_for_status()
        return r.json()['id']

    def assign(self, cid):
        r = self.client.post('/api/assignments', json={'case_ids': [cid]}, headers=self.headers)
        r.raise_for_status()
        self.assertTrue(r.json()['results'][0]['assigned'])

    def activity(self, cid, code, **extra):
        version = self.client.get('/api/cases/' + cid, headers=self.headers).json()['case']['version']
        r = self.client.post('/api/cases/' + cid + '/activities', headers=self.headers,
                             json=dict(code=code, expected_version=version, request_key=uuid4().hex, **extra))
        r.raise_for_status()

    def report(self, **params):
        response = self.client.get('/api/reports', params=dict(kind='collection', q='Laporan Uji', **params), headers=self.headers)
        response.raise_for_status()
        return response.json()

    def test_wib_inclusive_date_boundaries_and_export_parity(self):
        first = self.create()
        self.now += timedelta(days=1) - timedelta(seconds=1)
        self.headers = self.login('supervisor')
        last = self.create()
        self.now += timedelta(seconds=1)
        self.create()
        filters = dict(kind='collection', date_from='2026-10-28', date_to='2026-10-28', q='Laporan Uji')
        data = self.client.get('/api/reports', params=filters, headers=self.headers).json()
        self.assertEqual({r['id'] for r in data['items']}, {first, last})
        self.assertEqual(data['summary']['amount'], 2000000)
        response = self.client.get('/api/reports/export', params=filters, headers=self.headers)
        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.content.startswith(b'\xef\xbb\xbf'))
        rows = list(csv.DictReader(io.StringIO(response.content.decode('utf-8-sig'))))
        self.assertEqual([r['id'] for r in rows], [r['id'] for r in data['items']])
        self.assertTrue(all(r['date_basis'] == 'created_at' and r['date_to_wib'] == '2026-10-28' for r in rows))
        self.assertEqual(response.headers['cache-control'], 'no-store')
        audit = self.client.get('/api/audit', headers=self.headers).json()[0]
        self.assertEqual(audit['action'], 'export_report')
        self.assertEqual(json.loads(audit['detail'])['rows'], 2)

    def test_cycles_keep_partial_payment_per_assignment_and_exclude_superseded_rate(self):
        cid = self.create()
        self.assign(cid)
        self.activity(cid, 'payment', amount=200000)
        case = self.client.get('/api/cases/' + cid, headers=self.headers).json()['case']
        r = self.client.post('/api/cases/' + cid + '/reassign', headers=self.headers,
                             json={'expected_version': case['version'], 'reason': 'Alih siklus uji laporan'})
        r.raise_for_status()
        self.activity(cid, 'payment', amount=800000)
        data = self.report(view='cycles')
        self.assertEqual(data['summary']['realized'], 1000000)
        self.assertEqual((data['summary']['success'], data['summary']['superseded'], data['summary']['evaluated']), (1, 1, 1))
        self.assertEqual(data['summary']['success_rate'], 100)
        self.assertEqual({r['cycle']: r['realized'] for r in data['items']}, {1: 200000, 2: 800000})
        self.assertEqual(sum(g['realized'] for g in data['by_agent']), 1000000)
        filters = dict(kind='collection', view='cycles', q='Laporan Uji')
        rows = list(csv.DictReader(io.StringIO(self.client.get('/api/reports/export', params=filters, headers=self.headers).content.decode('utf-8-sig'))))
        self.assertEqual(sum(int(r['realized']) for r in rows), 1000000)

    def test_paid_late_is_no_success_and_overdue_is_still_active(self):
        paid, active = self.create(), self.create()
        self.assign(paid); self.assign(active)
        self.now += timedelta(hours=72, seconds=1)
        self.headers = self.login('supervisor')
        self.activity(paid, 'payment', amount=1000000)
        data = self.report(view='cycles')
        self.assertEqual((data['summary']['success'], data['summary']['no_success'], data['summary']['active'], data['summary']['overdue']), (0, 1, 1, 1))
        self.assertEqual(data['summary']['success_rate'], 0)
        overdue = self.report(view='cycles', status='overdue')
        self.assertEqual([r['case_id'] for r in overdue['items']], [active])
        self.assertIsNone(overdue['summary']['success_rate'])
        self.assertEqual(self.report(status='paid')['total'], 1)

    def test_cycle_filters_use_historical_agent_and_assignment_date(self):
        cid = self.create(difficulty='Medium', dpd=25)  # Initial score 63.2: team A.
        self.now += timedelta(days=1)
        self.headers = self.login('supervisor')
        self.assign(cid)
        self.activity(cid, 'unreachable')
        case = self.client.get('/api/cases/' + cid, headers=self.headers).json()['case']
        self.client.post('/api/cases/' + cid + '/reassign', headers=self.headers,
                         json={'expected_version': case['version'], 'reason': 'Riwayat tidak terhubung ke tim B'}).raise_for_status()
        historical = self.report(view='cycles', agent_id='SMG-col-A', date_from='2026-10-29', date_to='2026-10-29')
        self.assertEqual(historical['total'], 1)
        self.assertEqual(historical['items'][0]['outcome'], 'superseded')
        self.assertEqual(self.report(agent_id='SMG-col-A')['total'], 0)
        self.assertEqual(self.report(view='cycles', agent_id='SMG-col-B')['total'], 1)
        self.assertEqual(self.report(date_from='2026-10-29')['total'], 0)

    def test_origination_disbursement_and_rejection_separate_from_collection(self):
        paid, rejected = self.create('origination'), self.create('origination')
        self.assign(paid); self.assign(rejected)
        self.activity(paid, 'documents'); self.activity(paid, 'qualified')
        self.activity(paid, 'disburse', amount=1000000)
        self.activity(rejected, 'reject', note='Penolakan simulasi laporan')
        for view in ['cases', 'cycles']:
            data = self.client.get('/api/reports', params=dict(kind='origination', view=view, q='Laporan Uji'), headers=self.headers).json()
            self.assertEqual((data['total'], data['summary']['realized']), (2, 1000000))
        self.assertEqual((data['summary']['success'], data['summary']['no_success']), (1, 1))
        self.assertEqual(self.report()['total'], 0)

    def test_pagination_summary_whole_result_export_beyond_200_literal_and_empty(self):
        # Fixture expansion is local to this test database.
        template = self.create(name='Laporan Uji %_')
        with self.app.state.db.connect(write=True) as db:
            base = dict(db.execute('SELECT * FROM cases WHERE id=?', (template,)).fetchone())
            for i in range(210):
                row = dict(base, id=f'REPORT-{i:03}')
                db.execute(f'INSERT INTO cases ({",".join(row)}) VALUES ({",".join("?" for _ in row)})', tuple(row.values()))
        all_ids = []
        for offset in range(0, 225, 25):
            data = self.report(offset=offset, limit=25)
            self.assertEqual((data['total'], data['summary']['total'], data['summary']['amount']), (211, 211, 211000000))
            all_ids.extend(r['id'] for r in data['items'])
        self.assertEqual(len(set(all_ids)), 211)
        exported = self.client.get('/api/reports/export', params=dict(kind='collection', q='%_'), headers=self.headers)
        rows = list(csv.DictReader(io.StringIO(exported.content.decode('utf-8-sig'))))
        self.assertEqual({r['id'] for r in rows}, set(all_ids))
        empty = self.report(date_to='2020-01-01')
        self.assertEqual(empty['summary']['total'], 0)
        self.assertEqual(empty['by_agent'], [])
        header = self.client.get('/api/reports/export', params=dict(kind='collection', date_to='2020-01-01'), headers=self.headers)
        self.assertEqual(len(list(csv.reader(io.StringIO(header.content.decode('utf-8-sig'))))), 1)

    def test_region_agent_validation_scope_and_session_security(self):
        a = self.create(); self.assign(a)
        self.create(region_id='BDG')
        self.assertEqual(self.report(region_id='SMG', agent_id='SMG-col-A')['total'], 1)
        self.assertEqual(self.report(agent_id='unassigned')['total'], 1)
        for path in ['/api/reports', '/api/reports/export']:
            agent = self.login('smg-col-a')
            self.assertEqual(self.client.get(path, params={'kind': 'collection'}, headers=agent).status_code, 403)
            self.assertEqual(self.client.get(path, params={'kind': 'collection'}).status_code, 401)
            for params in [dict(date_from='2026-11-01', date_to='2026-10-01'), dict(date_from='oops'),
                           dict(region_id='UNKNOWN'), dict(agent_id='SMG-ori-A'), dict(region_id='BDG', agent_id='SMG-col-A'),
                           dict(view='cycles', agent_id='unassigned'), dict(view='cycles', status='paid'),
                           dict(status='rejected'), dict(date_to='9999-12-31'), dict(date_from='0001-01-01')]:
                self.assertEqual(self.client.get(path, params=dict(kind='collection', **params), headers=self.headers).status_code, 422, params)

    def test_csv_formula_whitespace_quotes_unicode_no_unfiltered_data(self):
        dangerous = ['=1+1', '+cmd', '-1+2', '@SUM(A1)', '  =1+1', '\t=1', '"kutip", Nama Ω']
        ids = [self.create(name=name, region_id='BDG') for name in dangerous]
        with self.app.state.db.connect(write=True) as db:
            for cid, name in zip(ids, dangerous):
                db.execute('UPDATE cases SET customer=? WHERE id=?', (name, cid))
        response = self.client.get('/api/reports/export', params=dict(kind='collection', region_id='BDG', date_from='2026-10-28'), headers=self.headers)
        rows = list(csv.DictReader(io.StringIO(response.content.decode('utf-8-sig'))))
        self.assertTrue(set(ids) <= {r['id'] for r in rows})
        self.assertTrue(all(r['region_id'] == 'BDG' for r in rows))
        self.assertEqual({r['customer'] for r in rows if r['id'] in ids}, {"'" + name if name.lstrip()[:1] in '=+-@' else name for name in dangerous})
