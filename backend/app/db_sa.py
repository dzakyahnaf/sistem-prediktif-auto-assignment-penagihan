"""SQLAlchemy connections and a bound-SQL bridge for the existing services."""
from collections.abc import Mapping
from contextlib import contextmanager
from pathlib import Path
import re
import threading
from alembic import command
from alembic.config import Config
import sqlalchemy as sa
from sqlalchemy.pool import NullPool
from .sqlite_legacy import Database as LegacySQLite

WRITE_LOCK = 739102601
SCHEMA_HEAD = '0006_hardening'
_migration_guard = threading.Lock()

class Row(Mapping):
    def __init__(self, row): self.mapping = row._mapping
    def __getitem__(self, key): return tuple(self.mapping.values())[key] if isinstance(key, int) else self.mapping[key]
    def __iter__(self): return iter(self.mapping)
    def __len__(self): return len(self.mapping)

class Result:
    def __init__(self, result, lastrowid=None): self.result, self.lastrowid = result, lastrowid
    def fetchone(self):
        row = self.result.fetchone()
        return None if row is None else Row(row)
    def fetchall(self): return [Row(r) for r in self.result.fetchall()]
    def __iter__(self): return (Row(r) for r in self.result)

def bind_sql(sql, parameters):
    """Bind placeholders outside quoted literals; never interpolate user values."""
    parts = re.split(r"('(?:''|[^'])*')", sql)
    index = 0
    def placeholder(match):
        nonlocal index
        name = f'p{index}'; index += 1
        return ':' + name
    for i in range(0, len(parts), 2): parts[i] = re.sub(r'\?', placeholder, parts[i])
    if index != len(parameters): raise ValueError('SQL parameter count mismatch')
    # Legacy contract stores active/documents as 0/1 on both backends.
    return ''.join(parts), {f'p{i}': int(value) if isinstance(value,bool) else value for i, value in enumerate(parameters)}

class Connection:
    def __init__(self, connection): self.raw = connection
    def execute(self, sql, parameters=()):
        if sql.strip().upper() == 'BEGIN': return None  # Context already starts a snapshot.
        sql, bound = bind_sql(sql, parameters)
        identity = re.match(r'\s*INSERT INTO (activities|assignments|audit)\s*\(', sql, re.I)
        if self.raw.dialect.name == 'postgresql':
            parts=re.split(r"('(?:''|[^'])*')",sql)
            for i in range(0,len(parts),2):parts[i]=re.sub(r'\bLIKE\b','ILIKE',parts[i])
            sql=''.join(parts)
            if identity: sql += ' RETURNING id'
        result = self.raw.execute(sa.text(sql), bound)
        if self.raw.dialect.name == 'postgresql':
            last = result.scalar_one() if identity else None
        else:
            last = result.lastrowid
        return Result(result, last)
    def executemany(self, sql, parameters):
        for row in parameters: self.execute(sql, row)
    def commit(self): self.raw.commit()

class Database:
    def __init__(self, path):
        value = str(path)
        if value.startswith('postgresql://'): value = value.replace('postgresql://','postgresql+psycopg://',1)
        self.postgres = value.startswith('postgresql+psycopg://')
        self.path = value
        if self.postgres:
            options = sa.make_url(value).query.get('options','') + ' -c lock_timeout=15000 -c statement_timeout=60000 -c timezone=UTC'
            self.engine = sa.create_engine(value, pool_pre_ping=True, pool_size=5, max_overflow=5, hide_parameters=True,
                connect_args={'connect_timeout':5,'options':options})
        else:
            if '://' in value: raise ValueError('Use a SQLite file path or postgresql+psycopg URL.')
            Path(value).parent.mkdir(parents=True,exist_ok=True)
            self.engine = sa.create_engine(sa.URL.create('sqlite+pysqlite',database=value),poolclass=NullPool,
                connect_args={'timeout':15},hide_parameters=True)
    @contextmanager
    def connect(self, write=False):
        with self.engine.connect() as raw:
            if self.postgres:
                if write:
                    raw.begin()
                    # Preserve prototype single-writer semantics. Statements after
                    # the lock see the previous writer under READ COMMITTED.
                    raw.execute(sa.text('SELECT pg_advisory_xact_lock(:key)'),{'key':WRITE_LOCK})
                else:
                    raw.execution_options(isolation_level='REPEATABLE READ')
                    raw.begin(); raw.exec_driver_sql('SET TRANSACTION READ ONLY')
            else:
                raw.exec_driver_sql('PRAGMA foreign_keys=ON')
                raw.exec_driver_sql('BEGIN IMMEDIATE' if write else 'BEGIN')
            try:
                yield Connection(raw)
                if write: raw.commit()
            except Exception:
                raw.rollback(); raise
    def initialize(self):
        # Alembic's EnvironmentContext is process-global, serialize startup upgrades.
        with _migration_guard:
            if not self.postgres: LegacySQLite(self.path).initialize()
            config = Config(str(Path(__file__).resolve().parents[1] / 'alembic.ini'))
            config.set_main_option('script_location',str(Path(__file__).resolve().parents[1] / 'migrations'))
            with self.engine.begin() as raw:
                if self.postgres: raw.exec_driver_sql('SELECT pg_advisory_xact_lock(739102602)')
                config.attributes['connection'] = raw
                command.upgrade(config,'head')
    def dispose(self): self.engine.dispose()
