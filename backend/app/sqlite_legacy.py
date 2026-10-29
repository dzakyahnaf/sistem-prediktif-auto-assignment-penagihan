import sqlite3
from contextlib import contextmanager
from pathlib import Path

SCHEMA = """
CREATE TABLE IF NOT EXISTS regions (id TEXT PRIMARY KEY, name TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS agents (
 id TEXT PRIMARY KEY, name TEXT NOT NULL, region_id TEXT NOT NULL REFERENCES regions(id),
 kind TEXT NOT NULL, team TEXT NOT NULL, channel TEXT NOT NULL,
 approach TEXT NOT NULL, capacity INTEGER NOT NULL CHECK(capacity > 0), active INTEGER NOT NULL DEFAULT 1
);
CREATE TABLE IF NOT EXISTS users (
 id TEXT PRIMARY KEY, username TEXT UNIQUE NOT NULL, password_hash TEXT NOT NULL,
 role TEXT NOT NULL, agent_id TEXT REFERENCES agents(id)
);
CREATE TABLE IF NOT EXISTS sessions (
 token_hash TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id), expires_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS cases (
 id TEXT PRIMARY KEY, kind TEXT NOT NULL, customer TEXT NOT NULL,
 region_id TEXT NOT NULL REFERENCES regions(id), difficulty TEXT NOT NULL,
 amount INTEGER NOT NULL CHECK(amount > 0), paid INTEGER NOT NULL DEFAULT 0,
 dpd INTEGER NOT NULL DEFAULT 0, income INTEGER NOT NULL DEFAULT 0,
 interest INTEGER NOT NULL DEFAULT 0, documents_complete INTEGER NOT NULL DEFAULT 0,
 status TEXT NOT NULL DEFAULT 'new', cycle INTEGER NOT NULL DEFAULT 0,
 agent_id TEXT REFERENCES agents(id), assigned_at TEXT, due_at TEXT,
 created_at TEXT NOT NULL, score REAL NOT NULL, score_version TEXT NOT NULL,
 source TEXT NOT NULL DEFAULT 'synthetic', version INTEGER NOT NULL DEFAULT 1
);
CREATE TABLE IF NOT EXISTS assignments (
 id INTEGER PRIMARY KEY AUTOINCREMENT, case_id TEXT NOT NULL REFERENCES cases(id),
 agent_id TEXT NOT NULL REFERENCES agents(id), cycle INTEGER NOT NULL,
 assigned_at TEXT NOT NULL, due_at TEXT NOT NULL, ended_at TEXT,
 outcome TEXT, score REAL NOT NULL, reason TEXT NOT NULL, actor_id TEXT NOT NULL REFERENCES users(id),
 UNIQUE(case_id, cycle)
);
CREATE TABLE IF NOT EXISTS activities (
 id INTEGER PRIMARY KEY AUTOINCREMENT, case_id TEXT NOT NULL REFERENCES cases(id),
 assignment_id INTEGER NOT NULL REFERENCES assignments(id), actor_id TEXT NOT NULL REFERENCES users(id),
 code TEXT NOT NULL, note TEXT NOT NULL, amount INTEGER NOT NULL DEFAULT 0,
 promise_date TEXT, created_at TEXT NOT NULL,
 request_key TEXT UNIQUE NOT NULL
);
CREATE TABLE IF NOT EXISTS audit (
 id INTEGER PRIMARY KEY AUTOINCREMENT, actor_id TEXT NOT NULL REFERENCES users(id),
 action TEXT NOT NULL, case_id TEXT, detail TEXT NOT NULL, created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS ix_cases_queue ON cases(kind, status, region_id);
CREATE INDEX IF NOT EXISTS ix_assignments_agent_time ON assignments(agent_id, assigned_at);
CREATE INDEX IF NOT EXISTS ix_activities_case ON activities(case_id, id);
CREATE TABLE IF NOT EXISTS import_batches (
 id TEXT PRIMARY KEY, actor_id TEXT NOT NULL REFERENCES users(id), kind TEXT NOT NULL,
 filename TEXT NOT NULL, file_sha256 TEXT NOT NULL, content BLOB,
 created_at TEXT NOT NULL, expires_at TEXT NOT NULL, state TEXT NOT NULL DEFAULT 'uploaded',
 revision INTEGER NOT NULL DEFAULT 0, metadata TEXT NOT NULL,
 preview TEXT, result TEXT
);
CREATE INDEX IF NOT EXISTS ix_import_batches_actor ON import_batches(actor_id,created_at);
CREATE TABLE IF NOT EXISTS import_case_refs (
 kind TEXT NOT NULL, source_key TEXT NOT NULL, source_ref TEXT NOT NULL,
 case_id TEXT NOT NULL UNIQUE REFERENCES cases(id), batch_id TEXT NOT NULL REFERENCES import_batches(id),
 PRIMARY KEY(kind,source_key)
);
CREATE TABLE IF NOT EXISTS assignment_overrides (
 request_key TEXT PRIMARY KEY, actor_id TEXT NOT NULL REFERENCES users(id),
 case_id TEXT NOT NULL REFERENCES cases(id), payload TEXT NOT NULL, result TEXT NOT NULL,
 created_at TEXT NOT NULL
);
"""


class Database:
    """One connection per operation. BEGIN IMMEDIATE serializes capacity updates."""

    def __init__(self, path: str):
        self.path = path
        Path(path).parent.mkdir(parents=True, exist_ok=True)

    @contextmanager
    def connect(self, write=False):
        conn = sqlite3.connect(self.path, timeout=15)
        conn.row_factory = sqlite3.Row
        conn.execute("PRAGMA foreign_keys=ON")
        try:
            if write:
                conn.execute("BEGIN IMMEDIATE")
            yield conn
            if write:
                conn.commit()
        except Exception:
            conn.rollback()
            raise
        finally:
            conn.close()

    def initialize(self):
        with self.connect() as conn:
            conn.execute("PRAGMA journal_mode=WAL")
            conn.executescript(SCHEMA)
            # Additive, restart-safe migrations preserve existing business rows.
            for table, columns in {
                'regions': {'active': 'INTEGER NOT NULL DEFAULT 1', 'version': 'INTEGER NOT NULL DEFAULT 1'},
                'agents': {'version': 'INTEGER NOT NULL DEFAULT 1'},
                'assignments': {'agent_name': 'TEXT', 'agent_team': 'TEXT', 'agent_channel': 'TEXT'},
            }.items():
                existing = {r['name'] for r in conn.execute(f'PRAGMA table_info({table})')}
                for name, definition in columns.items():
                    if name not in existing:
                        conn.execute(f'ALTER TABLE {table} ADD COLUMN {name} {definition}')
            conn.execute('''UPDATE assignments SET
                agent_name=COALESCE(agent_name,(SELECT name FROM agents WHERE id=agent_id)),
                agent_team=COALESCE(agent_team,(SELECT team FROM agents WHERE id=agent_id)),
                agent_channel=COALESCE(agent_channel,(SELECT channel FROM agents WHERE id=agent_id))
                WHERE agent_name IS NULL OR agent_team IS NULL OR agent_channel IS NULL''')
            if conn.execute('PRAGMA user_version').fetchone()[0] < 3:
                conn.execute('PRAGMA user_version = 3')
            conn.commit()
