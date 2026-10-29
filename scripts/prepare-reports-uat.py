"""Prepare report UAT in a NEW SQLite backup, without modifying the original."""
import argparse
from contextlib import closing
from datetime import datetime, timedelta, timezone
import json
from pathlib import Path
import runpy
import sqlite3
import sys
from uuid import uuid4

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'backend'))
from fastapi.testclient import TestClient
from app.main import create_app
from app.seed import DEMO_PASSWORD

fingerprint = runpy.run_path(str(ROOT / 'scripts/prepare-pagination-uat.py'))['fingerprint']


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--database', type=Path, default=ROOT / 'runtime/reports-uat.db')
    args = parser.parse_args()
    source = (ROOT / 'runtime/assignment.db').resolve()
    target = args.database.resolve()
    if source == target or target.exists():
        parser.error('Choose a new database; existing files are never overwritten.')
    target.parent.mkdir(parents=True, exist_ok=True)
    original = fingerprint(source)
    with closing(sqlite3.connect(source.as_uri() + '?mode=ro', uri=True)) as live:
        with closing(sqlite3.connect(target)) as copy:
            live.backup(copy)
    now = datetime(2026, 10, 24, 17, tzinfo=timezone.utc)  # 25 October WIB
    report = dict(database=str(target), source_fingerprint=original, cases={})
    with TestClient(create_app(str(target), lambda: now)) as client:
        headers = {}

        def login():
            response = client.post('/api/auth/login', json=dict(username='supervisor', password=DEMO_PASSWORD))
            response.raise_for_status()
            headers['Authorization'] = 'Bearer ' + response.json()['access_token']

        def post(path, payload):
            response = client.post(path, json=payload, headers=headers)
            response.raise_for_status()
            return response.json()

        def create(name, kind='collection', **extra):
            payload = dict(kind=kind, customer='UAT S4 ' + name, region_id='SMG', difficulty='Low', amount=1000000)
            if kind == 'origination':
                payload.update(income=5000000, interest=4)
            return post('/api/cases', dict(payload, **extra))['id']

        def assign(cid):
            result = post('/api/assignments', {'case_ids': [cid]})['results'][0]
            assert result['assigned']

        def activity(cid, code, **extra):
            case = client.get('/api/cases/' + cid, headers=headers).json()['case']
            return post('/api/cases/' + cid + '/activities', dict(code=code, expected_version=case['version'], request_key=uuid4().hex, **extra))

        login()
        split = create('Reassign Parsial', difficulty='Medium', dpd=25)
        assign(split); activity(split, 'payment', amount=200000); activity(split, 'unreachable')
        case = client.get('/api/cases/' + split, headers=headers).json()['case']
        post('/api/cases/' + split + '/reassign', {'expected_version': case['version'], 'reason': 'UAT S4 riwayat tidak terhubung pindah tim'})
        activity(split, 'payment', amount=800000)
        late, active = create('Lunas Terlambat'), create('Aktif Lewat SLA')
        assign(late); assign(active)
        ori, reject = create('Dicairkan', 'origination'), create('Ditolak', 'origination')
        assign(ori); activity(ori, 'documents'); activity(ori, 'qualified'); activity(ori, 'disburse', amount=1000000)
        assign(reject); activity(reject, 'reject', note='Penolakan sintetis laporan Sprint 4')
        now += timedelta(hours=73)
        login(); activity(late, 'payment', amount=1000000)
        for i in range(210):
            create(f'Portofolio {i + 1:03}', region_id='BDG')
        formula = create('Formula CSV')
        # Simulate untrusted imported/persisted text, including leading whitespace.
        with sqlite3.connect(target) as db:
            db.execute('UPDATE cases SET customer=? WHERE id=?', ('  =1+1, "Ω"', formula))
        report['cases'] = dict(split=split, late=late, active=active, disbursed=ori, rejected=reject, formula=formula)
        for kind in ['collection', 'origination']:
            for view in ['cases', 'cycles']:
                response = client.get('/api/reports', params=dict(kind=kind, view=view, q='UAT S4'), headers=headers)
                response.raise_for_status()
                report[f'{kind}_{view}'] = response.json()['summary']
    assert fingerprint(source) == original
    target.with_suffix('.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
