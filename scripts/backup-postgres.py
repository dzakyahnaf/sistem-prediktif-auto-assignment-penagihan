"""Create a pg_dump snapshot and optionally verify restore into a NEW project database."""
import argparse,json,os,subprocess,sys
from pathlib import Path
from uuid import uuid4
import sqlalchemy as sa
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'backend'))
from app.db import Database
from app.migrate import BUSINESS,digest

def snapshot(conn):
    names=[t.name for t in BUSINESS]+['sessions','migration_receipts','alembic_version']
    return {name:digest(conn.execute(sa.text(f'SELECT * FROM {name}')).mappings().all()) for name in names}

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--target',choices=['demo','uat'],default='demo')
    p.add_argument('--output',type=Path,required=True);p.add_argument('--report',type=Path,required=True)
    p.add_argument('--verify-restore',action='store_true');a=p.parse_args()
    if a.output.exists() or a.report.exists():p.error('Existing backup/report preserved; choose new paths.')
    c=json.loads((ROOT/'runtime/postgres-local.json').read_text());url=sa.make_url(c['database_url' if a.target=='demo' else 'uat_url'])
    env={**os.environ,'PGPASSWORD':url.password}
    args=['-h',url.host,'-p',str(url.port),'-U',url.username]
    db=Database(url.render_as_string(hide_password=False));a.output.parent.mkdir(parents=True,exist_ok=True)
    try:
        with db.connect() as reader:
            expected=snapshot(reader.raw)
            token=reader.raw.execute(sa.text('SELECT pg_export_snapshot()')).scalar_one()
            subprocess.run([str(Path(c['bin'])/'pg_dump.exe'),*args,'--format=custom','--no-owner','--snapshot',token,'--file',str(a.output),url.database],env=env,check=True)
        report=dict(database=url.database,backup=str(a.output.resolve()),tables=expected,restore_verified=False)
        if a.verify_restore:
            name='assignment_restore_s7_'+uuid4().hex[:12]
            admin=sa.create_engine(c['admin_url'],isolation_level='AUTOCOMMIT',hide_parameters=True)
            try:
                with admin.connect() as conn:conn.exec_driver_sql(f'CREATE DATABASE {name} OWNER assignment_app')
            finally:admin.dispose()
            subprocess.run([str(Path(c['bin'])/'pg_restore.exe'),*args,'--no-owner','--no-acl','--single-transaction','--exit-on-error','--dbname',name,str(a.output)],env=env,check=True)
            restored=Database(url.set(database=name).render_as_string(hide_password=False))
            try:
                with restored.connect() as conn:actual=snapshot(conn.raw)
                if expected!=actual:raise RuntimeError('Restored data does not match the exported snapshot.')
            finally:restored.dispose()
            report.update(restore_verified=True,restore_database=name)
        a.report.parent.mkdir(parents=True,exist_ok=True);a.report.write_text(json.dumps(report,indent=2),encoding='utf-8')
        print(json.dumps(dict(database=url.database,restore_verified=report['restore_verified'],backup_bytes=a.output.stat().st_size)))
    finally:db.dispose()
if __name__=='__main__':
    try:main()
    except Exception as exc:
        print(f'Backup/restore failed ({type(exc).__name__}). Existing databases were not overwritten; partial evidence retained.',file=sys.stderr);sys.exit(1)
