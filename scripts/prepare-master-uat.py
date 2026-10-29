"""Create a new, isolated Sprint 6 backup and workflow preconditions."""
import argparse
from contextlib import closing
import hashlib
import json
from pathlib import Path
import sqlite3
import sys
from uuid import uuid4

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'backend'))
from fastapi.testclient import TestClient
from app.main import create_app
from app.seed import DEMO_PASSWORD


def fingerprint(path, columns=None):
    result = {}
    with closing(sqlite3.connect(path.as_uri() + '?mode=ro', uri=True)) as db:
        tables = columns or {r[0]: [c[1] for c in db.execute(f'PRAGMA table_info({r[0]})')] for r in db.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name NOT IN ('sessions','sqlite_sequence') ORDER BY name")}
        for table, names in tables.items():
            # Identifiers come from SQLite's schema or this helper's own manifest.
            quoted = ','.join('"' + n.replace('"', '""') + '"' for n in names)
            rows = db.execute(f'SELECT {quoted} FROM "{table}" ORDER BY 1').fetchall()
            result[table] = dict(columns=names, count=len(rows), sha256=hashlib.sha256(json.dumps(rows, default=lambda b: hashlib.sha256(b).hexdigest()).encode()).hexdigest())
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--database', type=Path, default=ROOT / 'runtime/master-uat.db')
    args = parser.parse_args()
    source=(ROOT / 'runtime/assignment.db').resolve(); target=args.database.resolve()
    if source==target or target.exists(): parser.error('Choose a new database; existing databases are never overwritten.')
    original=fingerprint(source)
    target.parent.mkdir(parents=True,exist_ok=True)
    with closing(sqlite3.connect(source.as_uri()+'?mode=ro',uri=True)) as live, closing(sqlite3.connect(target)) as copy: live.backup(copy)
    report=dict(database=str(target),source_fingerprint=original,cases={})
    with TestClient(create_app(str(target))) as client:
        login=client.post('/api/auth/login',json=dict(username='supervisor',password=DEMO_PASSWORD));login.raise_for_status()
        headers={'Authorization':'Bearer '+login.json()['access_token']}
        def post(path,payload):
            r=client.post(path,json=payload,headers=headers);r.raise_for_status();return r.json()
        def create(name,kind='collection',**extra):
            p=dict(kind=kind,customer='UAT S6 '+name,region_id='SMG',difficulty='Low',amount=100000)
            if kind=='origination':p.update(income=5000000,interest=4,amount=1000000)
            return post('/api/cases',{**p,**extra})['id']
        def activity(cid,code,**extra):
            c=client.get('/api/cases/'+cid,headers=headers).json()['case']
            post(f'/api/cases/{cid}/activities',dict(code=code,expected_version=c['version'],request_key=uuid4().hex,**extra))
        medium=create('Penagihan Alih Tim',difficulty='Medium',dpd=15)
        ori=create('Pengajuan Terverifikasi',kind='origination')
        high=create('Penagihan Assignment Awal',difficulty='High')
        for cid in [medium,ori]: assert post('/api/assignments',dict(case_ids=[cid]))['results'][0]['assigned']
        activity(medium,'unreachable');activity(medium,'payment',amount=20000)
        activity(ori,'documents');activity(ori,'qualified')
        report['cases']=dict(medium=medium,origination=ori,high=high)
    assert fingerprint(source)==original
    report['uat_before_browser']=fingerprint(target)
    target.with_suffix('.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    print(json.dumps(dict(database=str(target),cases=report['cases'],counts={t:r['count'] for t,r in report['uat_before_browser'].items()}),indent=2))


if __name__=='__main__':main()
