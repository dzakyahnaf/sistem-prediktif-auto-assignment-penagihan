"""Verified, atomic, one-time copy from SQLite into an empty PostgreSQL target."""
from contextlib import closing
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import sqlite3
from uuid import uuid4
import sqlalchemy as sa
from .db import Database, SCHEMA_HEAD
from .tables import metadata

BUSINESS = [t for t in metadata.sorted_tables if t.name not in {'sessions','migration_receipts'}]

def digest(rows):
    canonical=sorted([dict(r) for r in rows],key=lambda r:json.dumps(r,sort_keys=True,default=str))
    data=json.dumps(canonical,sort_keys=True,ensure_ascii=True,default=lambda b: {'blob_sha256':hashlib.sha256(b).hexdigest()})
    return dict(count=len(rows),sha256=hashlib.sha256(data.encode()).hexdigest())

def sqlite_snapshot(path):
    with closing(sqlite3.connect(path.as_uri()+'?mode=ro',uri=True)) as conn:
        conn.row_factory=sqlite3.Row
        names=[r[0] for r in conn.execute("SELECT name FROM sqlite_master WHERE type='table' AND name NOT IN ('sqlite_sequence','sessions','alembic_version','migration_receipts') ORDER BY name")]
        return {name:digest(conn.execute(f'SELECT * FROM "{name}"').fetchall()) for name in names}

def migrate_sqlite(source, target_url, backup_dir, *, fail_after=None):
    source=Path(source).resolve(); backup_dir=Path(backup_dir).resolve()
    if not source.is_file(): raise ValueError('SQLite source does not exist.')
    target=Database(target_url)
    if not target.postgres: raise ValueError('Migration target must be PostgreSQL.')
    backup_dir.mkdir(parents=True,exist_ok=True)
    backup=backup_dir/f'assignment-{datetime.now(timezone.utc):%Y%m%dT%H%M%SZ}-{uuid4().hex[:10]}.db'
    if backup.exists() or backup==source: raise ValueError('Backup must be a new file.')
    with closing(sqlite3.connect(source.as_uri()+'?mode=ro',uri=True)) as live, closing(sqlite3.connect(backup)) as copy:
        live.backup(copy)
    original=sqlite_snapshot(backup)
    # Upgrade only the backup; source is never opened in write mode.
    staged=Database(str(backup));staged.initialize();staged.dispose()
    rows={}
    with closing(sqlite3.connect(backup)) as conn:
        conn.row_factory=sqlite3.Row
        if conn.execute('PRAGMA foreign_key_check').fetchall(): raise ValueError('Source has broken foreign keys.')
        for table in BUSINESS:
            rows[table.name]=[dict(r) for r in conn.execute(f'SELECT * FROM "{table.name}"')]
        sequences=dict(conn.execute('SELECT name,seq FROM sqlite_sequence'))
    expected={t:digest(r) for t,r in rows.items()}
    source_key=hashlib.sha256(json.dumps(expected,sort_keys=True).encode()).hexdigest()
    target.initialize()
    try:
        with target.connect(write=True) as conn:
            raw=conn.raw
            prior=raw.execute(sa.select(metadata.tables['migration_receipts']).where(metadata.tables['migration_receipts'].c.source_sha256==source_key)).mappings().first()
            if prior:
                return dict(json.loads(prior['manifest']),replayed=True,backup=str(backup))
            # A later additive Alembic revision can add empty tables/defaults to
            # the normalized copy and change its key. Recognize the SAME raw
            # source snapshot from the older receipt, without recopying a target
            # that may already have newer business/analytical records.
            for saved in raw.execute(sa.select(metadata.tables['migration_receipts'].c.manifest)).scalars():
                manifest=json.loads(saved)
                if manifest.get('source_original')==original:
                    return dict(manifest,replayed=True,backup=str(backup))
            for table in metadata.sorted_tables:
                if raw.execute(sa.select(sa.func.count()).select_from(table)).scalar_one():
                    raise ValueError('Target is not empty. No merge/overwrite is permitted.')
            for i,table in enumerate(BUSINESS):
                if rows[table.name]: raw.execute(table.insert(),rows[table.name])
                if fail_after==i: raise RuntimeError('Injected migration interruption')
            actual={table.name:digest(raw.execute(sa.select(table)).mappings().all()) for table in BUSINESS}
            if expected!=actual: raise RuntimeError('Row verification failed; target transaction rolled back.')
            for name in ['assignments','activities','audit']:
                maximum=raw.execute(sa.text(f'SELECT MAX(id) FROM {name}')).scalar_one() or 0
                value=max(maximum,sequences.get(name,0))
                raw.execute(sa.text("SELECT setval(pg_get_serial_sequence(:table,'id'), :value, :called)"),dict(table=name,value=max(1,value),called=value>0))
            report=dict(source=str(source),backup=str(backup),schema=SCHEMA_HEAD,source_original=original,tables=actual,
                        sequences=sequences,sessions_copied=0,verified=True,created_at=datetime.now(timezone.utc).isoformat())
            raw.execute(metadata.tables['migration_receipts'].insert().values(source_sha256=source_key,created_at=report['created_at'],manifest=json.dumps(report)))
        return dict(report,replayed=False)
    finally:target.dispose()
