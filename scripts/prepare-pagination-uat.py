"""Create an isolated copy with >200 cases per workflow for browser UAT.

Never overwrites an existing database or modifies runtime/assignment.db.
Run from the project with .venv/Scripts/python.exe.
"""
import argparse
from contextlib import closing
import hashlib
import json
from pathlib import Path
import sqlite3
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'backend'))

from fastapi.testclient import TestClient
from app.main import create_app
from app.seed import DEMO_PASSWORD


def fingerprint(path):
    result = {}
    with closing(sqlite3.connect(path.as_uri() + '?mode=ro', uri=True)) as conn:
        for table in ['regions', 'agents', 'users', 'cases', 'assignments', 'activities', 'audit']:
            rows = conn.execute(f'SELECT * FROM {table} ORDER BY 1').fetchall()
            result[table] = {'count': len(rows), 'sha256': hashlib.sha256(json.dumps(rows).encode()).hexdigest()}
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--database', type=Path, default=ROOT / 'runtime' / 'pagination-uat.db')
    args = parser.parse_args()
    source = (ROOT / 'runtime' / 'assignment.db').resolve()
    target = args.database.resolve()
    if target == source or target.exists():
        parser.error('Choose a new test database path; existing databases are never overwritten.')
    target.parent.mkdir(parents=True, exist_ok=True)
    original = fingerprint(source)
    with closing(sqlite3.connect(source.as_uri() + '?mode=ro', uri=True)) as live:
        with closing(sqlite3.connect(target)) as copy:
            live.backup(copy)
    report = {'database': str(target), 'source_fingerprint': original, 'targets': {}}
    with TestClient(create_app(str(target))) as client:
        login = client.post('/api/auth/login', json={'username': 'supervisor', 'password': DEMO_PASSWORD})
        login.raise_for_status()
        headers = {'Authorization': 'Bearer ' + login.json()['access_token']}

        def create(kind, name, **overrides):
            payload = dict(kind=kind, customer=name, region_id='SMG', difficulty='Low', amount=200000)
            if kind == 'origination':
                payload.update(income=5000000, interest=5)
            payload.update(overrides)
            response = client.post('/api/cases', json=payload, headers=headers)
            response.raise_for_status()
            return response.json()

        for kind, title in [('collection', 'Penagihan'), ('origination', 'Pengajuan')]:
            for i in range(210):
                create(kind, f'UAT S3B {title} {i + 1:03}')
            low_priority = dict(difficulty='High')
            if kind == 'collection':
                low_priority.update(dpd=3650)
            else:
                low_priority.update(income=1, interest=1, amount=1000000000)
            case = create(kind, f'UAT S3B Target Akhir {title}', **low_priority)
            report['targets'][kind] = {'id': case['id'], 'name': case['customer']}

        for code, title in [('documents', 'Dokumen'), ('reject', 'Ditolak')]:
            case = create('origination', f'UAT S3B Status {title}')
            client.post('/api/assignments', json={'case_ids': [case['id']]}, headers=headers).raise_for_status()
            latest = client.get('/api/cases/' + case['id'], headers=headers).json()['case']
            client.post('/api/cases/' + case['id'] + '/activities', json={
                'expected_version': latest['version'], 'request_key': 'pagination-fixture-' + code,
                'code': code, 'note': 'Skenario status sintetis pagination',
            }, headers=headers).raise_for_status()
        report['dashboard'] = client.get('/api/dashboard', headers=headers).json()['streams']
    # Compute positions after adding all status fixtures too.
    with closing(sqlite3.connect(target)) as conn:
        for kind, case in report['targets'].items():
            score = conn.execute('SELECT score FROM cases WHERE id=?', (case['id'],)).fetchone()[0]
            position = 1 + conn.execute('SELECT COUNT(*) FROM cases WHERE kind=? AND (score>? OR (score=? AND id<?))',
                (kind, score, score, case['id'])).fetchone()[0]
            assert position > 200
            case['position'] = position
    assert fingerprint(source) == original
    output = target.with_suffix('.json')
    output.write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
