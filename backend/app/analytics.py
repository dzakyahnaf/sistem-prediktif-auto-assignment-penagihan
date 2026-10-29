"""Supervisor-only immutable historical runs, paging and a verified export bundle."""
from datetime import timezone
import io
import json
from typing import Literal
from uuid import uuid4
import zipfile

from fastapi import Depends, HTTPException, Query
from fastapi.responses import Response
from pydantic import Field

from .historical import HistoryConfig, content_hash, create_dataset, dictionary, encode
from .domain import timestamp
from .service import audit
from .tables import metadata


class HistoryRequest(HistoryConfig):
    request_key: str = Field(min_length=12, max_length=80, pattern=r'^[A-Za-z0-9_-]+$')


def require_run(conn, run_id):
    row = conn.execute('SELECT * FROM analytics_runs WHERE id=?', (run_id,)).fetchone()
    if row is None: raise HTTPException(404, 'Dataset historis tidak ditemukan.')
    return dict(row)


def public_run(row):
    return dict(id=row['id'], created_at=row['created_at'], config=json.loads(row['config']),
                manifest=json.loads(row['manifest']))


def replay(conn, key, config, actor):
    row = conn.execute('SELECT * FROM analytics_runs WHERE request_key=?', (key,)).fetchone()
    if row is None: return None
    if row['config'] != encode(config) or row['actor_id'] != actor['id']:
        raise HTTPException(409, 'Kunci pembuatan sudah digunakan dengan konfigurasi/akun berbeda.')
    return dict(**public_run(row), replayed=True)


def register_analytics_routes(app, db, clock, supervisor):
    @app.get('/api/analytics/runs')
    def runs(offset: int = Query(0, ge=0), limit: int = Query(20, ge=1, le=100), user=Depends(supervisor)):
        with db.connect() as conn:
            total = conn.execute('SELECT COUNT(*) FROM analytics_runs').fetchone()[0]
            return dict(total=total, items=[public_run(r) for r in conn.execute(
                'SELECT * FROM analytics_runs ORDER BY created_at DESC,id DESC LIMIT ? OFFSET ?', (limit, offset))])

    @app.post('/api/analytics/runs', status_code=201)
    def generate(payload: HistoryRequest, user=Depends(supervisor)):
        config = HistoryConfig(**payload.model_dump(exclude={'request_key'}))
        serialized = config.model_dump(mode='json')
        with db.connect() as conn:
            existing = replay(conn, payload.request_key, serialized, user)
            if existing: return existing
        if config.as_of > clock().astimezone(timezone.utc).date():
            raise HTTPException(422, 'Tanggal observasi tidak boleh di masa depan.')
        # Pure bounded CPU work takes place before taking the shared write lock.
        bundle, manifest = create_dataset(config)
        run_id = 'HIST-' + uuid4().hex[:12].upper()
        row = dict(id=run_id, request_key=payload.request_key, actor_id=user['id'], created_at=timestamp(clock()),
                   config=encode(serialized), manifest=encode(manifest), data_sha256=manifest['data_sha256'])
        with db.connect(write=True) as conn:
            existing = replay(conn, payload.request_key, serialized, user)
            if existing: return existing
            conn.raw.execute(metadata.tables['analytics_runs'].insert(), row)
            for name, records in bundle.items():
                table = metadata.tables['analytics_' + name]
                values = [dict(run_id=run_id, record_id=r['id'], payload=encode(r),
                               **({k:r[k] for k in ('kind', 'stage', 'split')} if name == 'samples' else {})) for r in records]
                for start in range(0, len(values), 500): conn.raw.execute(table.insert(), values[start:start+500])
            audit(conn, user, 'analytics_generate', None, dict(run_id=run_id, data_sha256=manifest['data_sha256'], counts=manifest['counts']), clock())
        return dict(**public_run(row), replayed=False)

    @app.get('/api/analytics/runs/{run_id}')
    def detail(run_id: str, user=Depends(supervisor)):
        with db.connect() as conn: return dict(**public_run(require_run(conn, run_id)), dictionary=dictionary())

    @app.get('/api/analytics/runs/{run_id}/samples')
    def samples(run_id: str, kind: Literal['collection', 'origination'] = 'collection',
                stage: Literal['initial', 'reassignment'] = 'initial',
                split: Literal['all', 'train', 'validation', 'test', 'excluded'] = 'all',
                offset: int = Query(0, ge=0), limit: int = Query(25, ge=1, le=200), user=Depends(supervisor)):
        with db.connect() as conn:
            require_run(conn, run_id)
            where = ' WHERE run_id=? AND kind=? AND stage=?'
            args = [run_id, kind, stage]
            if split != 'all': where += ' AND split=?'; args.append(split)
            total = conn.execute('SELECT COUNT(*) FROM analytics_samples' + where, args).fetchone()[0]
            return dict(total=total, offset=offset, limit=limit, items=[json.loads(r['payload']) for r in conn.execute(
                'SELECT payload FROM analytics_samples' + where + ' ORDER BY record_id LIMIT ? OFFSET ?', [*args, limit, offset])])

    @app.get('/api/analytics/runs/{run_id}/export')
    def export(run_id: str, user=Depends(supervisor)):
        with db.connect() as conn:
            row = require_run(conn, run_id)
            bundle = {name:[json.loads(r['payload']) for r in conn.execute(
                'SELECT payload FROM analytics_' + name + ' WHERE run_id=? ORDER BY record_id', (run_id,))]
                for name in ('cases', 'decisions', 'events', 'samples')}
        if content_hash(bundle) != row['data_sha256']:
            raise HTTPException(409, 'Hash dataset tidak cocok; unduhan diblokir. Periksa penyimpanan.')
        stream = io.BytesIO()
        with zipfile.ZipFile(stream, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
            files = {name+'.jsonl': ''.join(encode(r)+'\n' for r in records) for name, records in bundle.items()}
            files.update({'manifest.json': encode(public_run(row)), 'dictionary.json': encode(dictionary())})
            for name, content in files.items():
                info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
                info.compress_type = zipfile.ZIP_DEFLATED
                archive.writestr(info, content.encode())
        with db.connect(write=True) as conn:
            audit(conn, user, 'analytics_export', None, dict(run_id=run_id, data_sha256=row['data_sha256']), clock())
        return Response(stream.getvalue(), media_type='application/zip',
                        headers={'Content-Disposition': f'attachment; filename="{row["id"]}-synthetic.zip"'})
