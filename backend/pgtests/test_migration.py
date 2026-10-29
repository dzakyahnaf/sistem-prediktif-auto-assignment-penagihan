import hashlib,io,json,sqlite3,tempfile,unittest
from contextlib import closing
from pathlib import Path
from uuid import uuid4
from alembic import command
from alembic.config import Config
from alembic.migration import MigrationContext
from alembic.autogenerate import compare_metadata
from fastapi.testclient import TestClient
from openpyxl import Workbook
import sqlalchemy as sa
from sqlalchemy.pool import NullPool
from app.db import Database,SCHEMA_HEAD
from app.db_sa import bind_sql
from app.main import create_app
from app.migrate import migrate_sqlite,sqlite_snapshot,digest,BUSINESS
from app.tables import metadata

ROOT=Path(__file__).resolve().parents[2]

class MigrationTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.source=Path(self.temp.name)/'source.db'
        with TestClient(create_app(str(self.source))) as client:
            h={'Authorization':'Bearer '+client.post('/api/auth/login',json={'username':'supervisor','password':'DemoAssignment!2026'}).json()['access_token']}
            case=client.post('/api/cases',headers=h,json=dict(kind='collection',customer='Migration Unicode Ω',region_id='SMG',difficulty='Low',amount=100000)).json()
            client.post('/api/assignments',headers=h,json=dict(case_ids=[case['id']]))
            self.cid=case['id']
            book=Workbook();ws=book.active;ws.append(['source_ref','customer','region_id','difficulty','amount','dpd']);ws.append(['000001','Draft Sintetis','SMG','Low',1000,0])
            stream=io.BytesIO();book.save(stream)
            response=client.post('/api/imports/upload?kind=collection&filename=test.xlsx',headers=h,content=stream.getvalue())
            self.assertEqual(response.status_code,201,response.text)
        c=json.loads((ROOT/'runtime/postgres-local.json').read_text());base=sa.make_url(c['uat_url'])
        self.schema='s7migration_'+uuid4().hex
        self.admin=sa.create_engine(base,poolclass=NullPool,hide_parameters=True)
        with self.admin.begin() as conn:conn.exec_driver_sql('CREATE SCHEMA '+self.schema)
        self.url=base.update_query_dict({'options':'-csearch_path='+self.schema}).render_as_string(hide_password=False)
        self.db=Database(self.url)
    def tearDown(self):
        self.db.dispose()
        assert self.schema.startswith('s7migration_') and len(self.schema)==44
        with self.admin.begin() as conn:conn.exec_driver_sql('DROP SCHEMA '+self.schema+' CASCADE')
        self.admin.dispose();self.temp.cleanup()
    def migrate(self,**kw):return migrate_sqlite(self.source,self.url,Path(self.temp.name)/'backups',**kw)

    def test_verified_copy_keeps_source_backup_blob_ids_hashes_and_invalidates_sessions(self):
        before=sqlite_snapshot(self.source);r=self.migrate()
        self.assertEqual(before,sqlite_snapshot(self.source));self.assertTrue(r['verified'])
        with self.db.connect() as conn:
            self.assertEqual(conn.execute('SELECT count(*) FROM sessions').fetchone()[0],0)
            self.assertTrue(conn.execute('SELECT content FROM import_batches').fetchone()[0].startswith(b'PK'))
            self.assertEqual(conn.execute('SELECT count(*) FROM users').fetchone()[0],13)
        self.assertTrue(Path(r['backup']).exists())
    def test_interruption_rolls_back_all_tables_and_retry_succeeds(self):
        with self.assertRaises(RuntimeError):self.migrate(fail_after=3)
        with self.db.connect() as conn:
            for table in BUSINESS:self.assertEqual(conn.execute(f'SELECT count(*) FROM {table.name}').fetchone()[0],0)
        self.assertTrue(self.migrate()['verified'])
    def test_refuses_nonempty_target_without_overwrite(self):
        self.db.initialize()
        with self.db.connect(write=True) as conn:conn.execute('INSERT INTO regions(id,name) VALUES (?,?)',('KEPT','Retained'))
        with self.assertRaises(ValueError):self.migrate()
        with self.db.connect() as conn:self.assertEqual(conn.execute('SELECT name FROM regions').fetchone()[0],'Retained')
    def test_replay_is_exactly_once_and_identity_sequences_advance(self):
        with closing(sqlite3.connect(self.source)) as conn:
            conn.execute("UPDATE sqlite_sequence SET seq=9000 WHERE name='audit'");conn.commit()
        first=self.migrate();second=self.migrate();self.assertTrue(second['replayed']);self.assertEqual(first['tables'],second['tables'])
        with self.db.connect(write=True) as conn:
            old=conn.execute('SELECT max(id) FROM audit').fetchone()[0]
            row=conn.execute('INSERT INTO audit(actor_id,action,detail,created_at) VALUES (?,?,?,?)',('USR-SUP','test','{}','2026-10-28T00:00:00+00:00'))
            self.assertGreater(row.lastrowid,old)
            self.assertGreater(row.lastrowid,9000)
        # A retry after later business mutations returns its original receipt, never recopies.
        self.assertTrue(self.migrate()['replayed'])
    def test_alembic_head_metadata_foreign_keys_and_restart(self):
        self.migrate();self.db.initialize();self.db.initialize()
        with self.db.engine.connect() as conn:
            self.assertEqual(conn.exec_driver_sql('SELECT version_num FROM alembic_version').scalar_one(),SCHEMA_HEAD)
            self.assertEqual(compare_metadata(MigrationContext.configure(conn),metadata),[])
        with self.assertRaises(sa.exc.IntegrityError):
            with self.db.connect(write=True) as conn:conn.execute('INSERT INTO users(id,username,password_hash,role,agent_id) VALUES (?,?,?,?,?)',('BAD','bad','hash','agent','missing'))
        with TestClient(create_app(self.url)) as client:self.assertEqual(client.get('/api/health').json()['storage'],'postgresql')
    def test_legacy_receipt_replay_after_additive_analytics_schema_keeps_later_data(self):
        # The pre-Sprint8 source has no analytics tables. Upgrade only its backup.
        with closing(sqlite3.connect(self.source)) as conn:
            conn.execute('DROP TABLE login_failures')
            for name in ('operation_requests','integration_attempts','integration_jobs','notifications','user_controls'):conn.execute('DROP TABLE '+name)
            for name in ('policy_revisions','segment_releases'):conn.execute('DROP TABLE '+name)
            for name in ('ml_predictions','case_origins','ml_serving','ml_transitions','ml_releases'):
                conn.execute('DROP TABLE '+name)
            for name in ('samples','events','decisions','cases','runs'):
                conn.execute('DROP TABLE analytics_'+name)
            conn.execute("UPDATE alembic_version SET version_num='0001_portable'");conn.commit()
        report=self.migrate()
        old_tables={k:v for k,v in report['tables'].items() if not k.startswith('analytics_')}
        old_key=hashlib.sha256(json.dumps(old_tables,sort_keys=True).encode()).hexdigest()
        historical={**report,'tables':old_tables,'schema':'0001_portable'}
        with self.db.connect(write=True) as conn:
            conn.execute('UPDATE migration_receipts SET source_sha256=?,manifest=?',(old_key,json.dumps(historical)))
            conn.execute('INSERT INTO regions(id,name) VALUES (?,?)',('AFTER','Later data retained'))
        replay=self.migrate()
        self.assertTrue(replay['replayed']);self.assertEqual(replay['schema'],'0001_portable')
        with self.db.connect() as conn:
            self.assertEqual(conn.execute('SELECT name FROM regions WHERE id=?',('AFTER',)).fetchone()[0],'Later data retained')
            self.assertEqual(conn.execute('SELECT count(*) FROM migration_receipts').fetchone()[0],1)
    def test_read_snapshot_is_repeatable_and_write_is_visible_after_commit(self):
        self.migrate()
        with self.db.connect() as reader:
            old=reader.execute('SELECT count(*) FROM regions').fetchone()[0]
            with self.db.connect(write=True) as writer:writer.execute('INSERT INTO regions(id,name) VALUES (?,?)',('NEXT','Next region'))
            self.assertEqual(reader.execute('SELECT count(*) FROM regions').fetchone()[0],old)
        with self.db.connect() as reader:self.assertEqual(reader.execute('SELECT count(*) FROM regions').fetchone()[0],old+1)
    def test_source_with_invalid_foreign_keys_is_rejected(self):
        with closing(sqlite3.connect(self.source)) as conn:
            conn.execute("UPDATE cases SET region_id='missing' WHERE id=?",(self.cid,));conn.commit()
        with self.assertRaises(ValueError):self.migrate()
    def test_bound_sql_quotes_question_marks_and_search_case_parity(self):
        sql,p=bind_sql("SELECT '?' AS literal, ? AS value",('a\' ? :p1',))
        self.assertEqual(sql,"SELECT '?' AS literal, :p0 AS value");self.assertEqual(p['p0'],"a' ? :p1")
        self.migrate()
        with self.db.connect() as conn:
            self.assertEqual(conn.execute('SELECT count(*) FROM regions WHERE name LIKE ?',('%semarang%',)).fetchone()[0],1)
            self.assertEqual(conn.execute("SELECT 'LIKE ?' AS literal").fetchone()[0],'LIKE ?')

if __name__=='__main__':unittest.main(verbosity=2)
