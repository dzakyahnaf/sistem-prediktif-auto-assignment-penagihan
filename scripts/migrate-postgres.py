"""Copy a SQLite snapshot to an empty PostgreSQL target; credentials never printed."""
import argparse,json,os,sys
from pathlib import Path
from uuid import uuid4
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'backend'))
from app.migrate import migrate_sqlite

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--source',type=Path,default=ROOT/'runtime/assignment.db')
    p.add_argument('--target',choices=['demo','uat'],default='demo')
    p.add_argument('--report',type=Path,required=True)
    p.add_argument('--activate',action='store_true',help='After verification, select the local demo database for default backend startup.')
    args=p.parse_args()
    if args.report.exists():p.error('Choose a new report path; previous evidence is preserved.')
    config_path=ROOT/'runtime/postgres-local.json'
    config=json.loads(config_path.read_text()) if config_path.exists() else None
    url=os.getenv('DATABASE_URL')
    if not url:
        if not config:p.error('Provide DATABASE_URL or initialize the project PostgreSQL cluster first.')
        url=config['database_url' if args.target=='demo' else 'uat_url']
    if args.activate and (args.target!='demo' or not config or url!=config['database_url']):
        p.error('--activate only supports the local demo target from postgres-local.json.')
    r=migrate_sqlite(args.source,url,ROOT/'runtime/backups')
    args.report.parent.mkdir(parents=True,exist_ok=True);args.report.write_text(json.dumps(r,indent=2),encoding='utf-8')
    if args.activate:
        config['active_backend']='postgresql'
        temporary=config_path.with_name(f'.postgres-local-{uuid4().hex}.tmp')
        try:
            temporary.write_text(json.dumps(config,indent=2),encoding='utf-8')
            temporary.replace(config_path)
        finally:
            temporary.unlink(missing_ok=True)
    print(json.dumps(dict(verified=r['verified'],replayed=r['replayed'],activated=args.activate,sessions_copied=r['sessions_copied'],tables={k:v['count'] for k,v in r['tables'].items()})))
if __name__=='__main__':
    try:main()
    except Exception as exc:
        print(f'Migration/cutover failed ({type(exc).__name__}). Source and backup retained; inspect the report if already written. No credentials printed.',file=sys.stderr)
        sys.exit(1)
