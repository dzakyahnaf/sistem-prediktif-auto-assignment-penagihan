"""Run existing workflow/report/import/master tests on isolated PostgreSQL schemas."""
import json
import argparse
from pathlib import Path
import re
import sys
import tempfile
import unittest
from uuid import uuid4
from contextlib import closing
import sqlalchemy as sa
from sqlalchemy.pool import NullPool

ROOT=Path(__file__).resolve().parents[1]
sys.path[:0]=[str(ROOT/'backend'),str(ROOT/'backend/tests')]
from fastapi.testclient import TestClient
from app.main import create_app
from app.migrate import migrate_sqlite

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--pattern',default='test*.py');args=parser.parse_args()
    config=json.loads((ROOT/'runtime/postgres-local.json').read_text())
    base=sa.make_url(config['uat_url'])
    if base.database!='assignment_uat_s7':raise ValueError('Tests require the project UAT database.')
    admin=sa.create_engine(base,poolclass=NullPool,hide_parameters=True)
    created_schemas=set()
    suite=unittest.TestLoader().discover(str(ROOT/'backend/tests'),pattern=args.pattern)
    # These two tests assert SQLite PRAGMA/drop-column/file upgrade behavior;
    # they remain in SQLite suite. All other existing scenarios run on PostgreSQL.
    sqlite_only={'test_role_validation_audit_and_restart_migration'}
    adapted=set()
    def cases(s):
        for item in s:
            if isinstance(item,unittest.TestSuite):yield from cases(item)
            else:yield item
    for test in cases(suite):
        cls=type(test)
        if test._testMethodName in sqlite_only:
            setattr(test,'setUp',lambda:None)
            setattr(test,'tearDown',lambda:None)
            setattr(test,test._testMethodName,lambda: unittest.TestCase.skipTest(test,'SQLite-specific PRAGMA migration; covered in SQLite suite'))
            continue
        if cls in adapted:continue
        adapted.add(cls); original=cls.setUp; cleanup=cls.tearDown
        def setup(self, original=original):
            original(self)
            old=self.path
            self.client.__exit__(None,None,None)
            schema='s7test_'+uuid4().hex
            if not re.fullmatch(r's7test_[0-9a-f]{32}',schema):raise ValueError('Invalid test schema')
            self.pg_schema=schema
            with admin.begin() as conn:conn.exec_driver_sql(f'CREATE SCHEMA {schema}')
            created_schemas.add(schema)
            url=base.update_query_dict({'options':f'-csearch_path={schema}'}).render_as_string(hide_password=False)
            self.pg_backup=tempfile.TemporaryDirectory()
            migrate_sqlite(old,url,self.pg_backup.name)
            self.path=url
            self.app=create_app(url,lambda:self.now)
            self.client=TestClient(self.app).__enter__()
            headers=self.login('supervisor')
            if hasattr(self,'headers'):self.headers=headers
            if hasattr(self,'h'):self.h=headers
        def teardown(self, cleanup=cleanup):
            cleanup(self)
            if hasattr(self,'app'):self.app.state.db.dispose()
            if hasattr(self,'pg_schema'):
                # Only the UUID schema created above, in the project UAT DB.
                if not re.fullmatch(r's7test_[0-9a-f]{32}',self.pg_schema):raise ValueError('Refusing schema cleanup')
                with admin.begin() as conn:conn.exec_driver_sql(f'DROP SCHEMA {self.pg_schema} CASCADE')
                created_schemas.discard(self.pg_schema)
            if hasattr(self,'pg_backup'):self.pg_backup.cleanup()
        cls.setUp=setup;cls.tearDown=teardown
    try:
        result=unittest.TextTestRunner(verbosity=2,failfast=True).run(suite)
        if not result.wasSuccessful():sys.exit(1)
    finally:
        for schema in created_schemas:
            if not re.fullmatch(r's7test_[0-9a-f]{32}',schema):raise ValueError('Refusing cleanup')
            with admin.begin() as conn:conn.exec_driver_sql(f'DROP SCHEMA IF EXISTS {schema} CASCADE')
        admin.dispose()

if __name__=='__main__':main()
