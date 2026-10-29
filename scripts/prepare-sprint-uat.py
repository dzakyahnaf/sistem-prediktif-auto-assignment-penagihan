"""Copy the current demo into a NEW schema; preserve every earlier UAT."""
import argparse,json,re,sys
from pathlib import Path
from uuid import uuid4
import sqlalchemy as sa
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'backend'))
from app.db import Database
from app.migrate import BUSINESS,digest

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--sprint',type=int,choices=[10,11,12,13],required=True);a=parser.parse_args()
    output=ROOT/f'runtime/sprint{a.sprint}-uat-config.json'
    if output.exists():raise ValueError('Existing UAT config preserved.')
    config=json.loads((ROOT/'runtime/postgres-local.json').read_text());base=sa.make_url(config['uat_url'])
    if base.database!='assignment_uat_s7':raise ValueError('Only the project UAT DB is allowed.')
    schema=f'uat_s{a.sprint}_'+uuid4().hex[:12]
    if not re.fullmatch(r'uat_s(10|11|12|13)_[0-9a-f]{12}',schema):raise ValueError('Invalid schema.')
    admin=sa.create_engine(base,hide_parameters=True)
    try:
        with admin.begin() as c:c.exec_driver_sql('CREATE SCHEMA '+schema)
    finally:admin.dispose()
    url=base.update_query_dict({'options':'-csearch_path='+schema}).render_as_string(hide_password=False)
    source=Database(config['database_url']);source.initialize();target=Database(url);target.initialize()
    try:
        with source.connect() as r,target.connect(write=True) as w:
            fingerprints={}
            for t in BUSINESS:
                rows=[dict(x) for x in r.raw.execute(sa.select(t)).mappings()]
                fingerprints[t.name]=digest(rows)
                for start in range(0,len(rows),500):w.raw.execute(t.insert(),rows[start:start+500])
            for n in ('assignments','activities','audit'):
                value=w.execute('SELECT max(id) FROM '+n).fetchone()[0] or 0
                w.raw.execute(sa.text("SELECT setval(pg_get_serial_sequence(:table,'id'),:value,:called)"),dict(table=n,value=max(value,1),called=value>0))
        with target.connect() as c:
            actual={t.name:digest(c.raw.execute(sa.select(t)).mappings().all()) for t in BUSINESS}
            if actual!=fingerprints:raise ValueError('Copy digest mismatch; new schema retained for inspection.')
        output.write_text(json.dumps(dict(url=url,schema=schema),indent=2),encoding='utf-8')
        (ROOT/f'runtime/sprint{a.sprint}-uat-baseline.json').write_text(json.dumps(fingerprints,indent=2),encoding='utf-8')
        print(json.dumps(dict(schema=schema,verified=True,cases=actual['cases']['count'],sessions_copied=0)))
    finally:source.dispose();target.dispose()

if __name__=='__main__':
    try:main()
    except Exception as exc:print(f'Preparation failed ({type(exc).__name__}); source data and earlier UAT retained.',file=sys.stderr);sys.exit(1)
