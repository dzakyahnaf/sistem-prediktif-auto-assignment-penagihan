"""Manage only the project's own loopback PostgreSQL cluster, never Windows services."""
import argparse
import json
from pathlib import Path
import secrets
import subprocess
import sys
from sqlalchemy import create_engine, text, URL, make_url
from sqlalchemy.pool import NullPool

ROOT=Path(__file__).resolve().parents[1]
RUNTIME=ROOT/'runtime'
CONFIG=RUNTIME/'postgres-local.json'
DATA=RUNTIME/'postgres-local-data'

def run(binary, *args):
    subprocess.run([str(binary),*map(str,args)],check=True)

def provision(config):
    engine=create_engine(config['admin_url'],isolation_level='AUTOCOMMIT',poolclass=NullPool,hide_parameters=True)
    try:
        with engine.connect() as conn:
            if not conn.execute(text("SELECT 1 FROM pg_roles WHERE rolname='assignment_app'")).first():
                password=make_url(config['database_url']).password
                if not password or any(c not in 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_' for c in password):
                    raise RuntimeError('Unexpected generated credential format.')
                conn.exec_driver_sql(f"CREATE ROLE assignment_app LOGIN PASSWORD '{password}' NOSUPERUSER NOCREATEDB NOCREATEROLE")
            for name in ['assignment_demo','assignment_uat_s7']:
                if not conn.execute(text('SELECT 1 FROM pg_database WHERE datname=:name'),dict(name=name)).first():
                    conn.exec_driver_sql(f'CREATE DATABASE {name} OWNER assignment_app')
    finally:engine.dispose()

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('action',choices=['init','start','stop','status','provision'])
    p.add_argument('--bin',type=Path,default=Path('C:/Program Files/PostgreSQL/18/bin'))
    p.add_argument('--port',type=int,default=15432)
    args=p.parse_args();RUNTIME.mkdir(exist_ok=True)
    ctl=args.bin/'pg_ctl.exe'
    if args.action=='init':
        if CONFIG.exists() or DATA.exists():p.error('Existing cluster/config preserved. Use start/status, not init.')
        password=secrets.token_urlsafe(32);app_password=secrets.token_urlsafe(32)
        pw=RUNTIME/'postgres-init-password.tmp';pw.write_text(password,encoding='utf-8')
        try:run(args.bin/'initdb.exe','-D',DATA,'-U','assignment_admin','--pwfile',pw,'--auth=scram-sha-256','--encoding=UTF8','--no-locale')
        finally:pw.unlink(missing_ok=True)
        admin=URL.create('postgresql+psycopg',username='assignment_admin',password=password,host='127.0.0.1',port=args.port,database='postgres')
        config=dict(bin=str(args.bin),port=args.port,admin_url=admin.render_as_string(hide_password=False))
        for key,name in [('database_url','assignment_demo'),('uat_url','assignment_uat_s7')]:
            config[key]=admin.set(username='assignment_app',password=app_password,database=name).render_as_string(hide_password=False)
        # Save recovery credentials before starting; never print them or overwrite them.
        CONFIG.write_text(json.dumps(config,indent=2),encoding='utf-8')
        run(ctl,'-D',DATA,'-l',RUNTIME/'postgres-local.log','-o',f'-h 127.0.0.1 -p {args.port}','-w','start')
        provision(config)
        print('Project PostgreSQL initialized on loopback. Credentials saved only in runtime/postgres-local.json.')
        return
    if not CONFIG.exists() or not (DATA/'PG_VERSION').exists():p.error('Project cluster is not initialized.')
    config=json.loads(CONFIG.read_text());ctl=Path(config['bin'])/'pg_ctl.exe'
    if args.action=='start':run(ctl,'-D',DATA,'-l',RUNTIME/'postgres-local.log','-o',f'-h 127.0.0.1 -p {config["port"]}','-w','start')
    elif args.action=='stop':run(ctl,'-D',DATA,'-m','fast','-w','stop')
    elif args.action=='provision':provision(config)
    else:run(ctl,'-D',DATA,'status')

if __name__=='__main__':main()
