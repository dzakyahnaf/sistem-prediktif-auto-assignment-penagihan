"""Read-only table fingerprints for restart/backup evidence; never prints URLs."""
import argparse,json,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'backend'))
from app.db import Database
from app.migrate import BUSINESS,digest

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--config',type=Path,default=ROOT/'runtime/postgres-local.json');p.add_argument('--output',type=Path,required=True);p.add_argument('--compare',type=Path);a=p.parse_args()
    if a.output.exists():p.error('Evidence already exists; choose a new path.')
    cfg=json.loads(a.config.read_text());db=Database(cfg.get('url') or cfg['database_url'])
    try:
        with db.connect() as c:
            tables={n:digest(c.execute('SELECT * FROM '+n).fetchall()) for n in [t.name for t in BUSINESS]+['sessions','migration_receipts','alembic_version']}
        if a.compare and json.loads(a.compare.read_text())!=tables:raise ValueError('Restart fingerprints differ; investigate before claiming persistence.')
        a.output.write_text(json.dumps(tables,indent=2),encoding='utf-8')
        print(json.dumps(dict(tables=len(tables),restart_equal=True if a.compare else None,counts={k:v['count'] for k,v in tables.items()})))
    finally:db.dispose()

if __name__=='__main__':
    try:main()
    except Exception as exc:print(f'Snapshot failed ({type(exc).__name__}); database not modified.',file=sys.stderr);sys.exit(1)
