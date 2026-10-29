"""Copy demo into a NEW isolated PostgreSQL schema and add aged synthetic cases."""
import json
from pathlib import Path
import re
import sys
from datetime import datetime,timedelta,timezone
from uuid import uuid4
import sqlalchemy as sa
from fastapi.testclient import TestClient
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'backend'))
from app.db import Database
from app.tables import metadata
from app.migrate import BUSINESS
from app.main import create_app
from app.seed import DEMO_PASSWORD


def main():
    output=ROOT/'runtime/model-uat-config.json'
    if output.exists():raise ValueError('Existing UAT config preserved; choose a new fixture script output before rerunning.')
    c=json.loads((ROOT/'runtime/postgres-local.json').read_text());base=sa.make_url(c['uat_url'])
    if base.database!='assignment_uat_s7':raise ValueError('Only the project UAT database is permitted.')
    schema='uat_s9_'+uuid4().hex[:12]
    if not re.fullmatch(r'uat_s9_[a-f0-9]{12}',schema):raise ValueError('Invalid schema.')
    admin=sa.create_engine(base,hide_parameters=True)
    try:
        with admin.begin() as conn:conn.exec_driver_sql('CREATE SCHEMA '+schema)
    finally:admin.dispose()
    url=base.update_query_dict({'options':'-csearch_path='+schema}).render_as_string(hide_password=False)
    source=Database(c['database_url']);target=Database(url);target.initialize()
    try:
        with source.connect() as reader,target.connect(write=True) as writer:
            for table in BUSINESS:
                rows=[dict(r) for r in reader.raw.execute(sa.select(table)).mappings()]
                for start in range(0,len(rows),500):writer.raw.execute(table.insert(),rows[start:start+500])
            for name in ('assignments','activities','audit'):
                value=writer.execute('SELECT max(id) FROM '+name).fetchone()[0] or 0
                writer.raw.execute(sa.text("SELECT setval(pg_get_serial_sequence(:table,'id'),:value,:called)"),dict(table=name,value=max(value,1),called=value>0))
    finally:source.dispose();target.dispose()
    now=datetime.now(timezone.utc).replace(microsecond=0)
    timer={'now':now}
    fixtures={}
    with TestClient(create_app(url,lambda:timer['now'],seed=False)) as client:
        for kind,days in [('collection',3),('origination',10)]:
            timer['now']=now-timedelta(days=days,hours=2)
            login=client.post('/api/auth/login',json=dict(username='supervisor',password=DEMO_PASSWORD));assert login.status_code==200
            h={'Authorization':'Bearer '+login.json()['access_token']}
            def request(method,path,body):
                r=client.request(method,path,headers=h,json=body)
                if r.status_code>=400:raise RuntimeError('Fixture API failed: '+str(r.status_code))
                return r.json()
            p=dict(kind=kind,customer='UAT S9 Histori '+kind,region_id='SMG',difficulty='Medium',amount=5000000)
            if kind=='origination':p.update(income=10000000,interest=4)
            else:p['dpd']=15
            case=request('POST','/api/cases',p);cid=case['id']
            request('POST','/api/assignments',dict(case_ids=[cid]));timer['now']+=timedelta(hours=1)
            activities=[('unreachable',0),('payment',1500000)] if kind=='collection' else [('documents',0),('qualified',0)]
            for code,amount in activities:
                detail=client.get('/api/cases/'+cid,headers=h).json()
                request('POST','/api/cases/'+cid+'/activities',dict(code=code,amount=amount,note='Fixture historis S9 sintetis',expected_version=detail['case']['version'],request_key=uuid4().hex))
            fixtures[kind]=cid
    output.write_text(json.dumps(dict(url=url,schema=schema,fixtures=fixtures),indent=2),encoding='utf-8')
    print(json.dumps(dict(schema=schema,fixtures=fixtures,sessions_copied=0)))


if __name__=='__main__':
    try:main()
    except Exception as exc:
        print(f'UAT preparation failed ({type(exc).__name__}); source unchanged, new schema retained.',file=sys.stderr);sys.exit(1)
