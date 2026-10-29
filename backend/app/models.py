"""Immutable model packages, verified report/export and atomic serving lifecycle."""
import io
import json
from uuid import uuid4
import zipfile
from fastapi import Depends, HTTPException, Query
from fastapi.responses import Response
from pydantic import Field, model_validator
from .schemas import Input
from .historical import HistoryConfig, FEATURE_VERSION, VERSION, content_hash, encode, validate_bundle
from .analytics import require_run
from .model_engine import train_release
from .scoring import serving_state, valid_artifact
from .service import audit
from .domain import timestamp


class TrainInput(Input):
    run_id: str = Field(min_length=5,max_length=64)
    request_key: str = Field(min_length=12,max_length=80,pattern=r'^[A-Za-z0-9_-]+$')


class ServingInput(Input):
    release_id: str | None = Field(default=None,min_length=5,max_length=64)
    expected_revision: int = Field(ge=0,strict=True)
    reason: str = Field(min_length=10,max_length=500)
    request_key: str = Field(min_length=12,max_length=80,pattern=r'^[A-Za-z0-9_-]+$')
    demo_ack: bool = False

    @model_validator(mode='after')
    def acknowledgement(self):
        if self.release_id and not self.demo_ack: raise ValueError('Aktivasi hanya untuk demo sintetis; pengakuan diperlukan.')
        return self


def public_release(row):
    return dict(id=row['id'],run_id=row['run_id'],created_at=row['created_at'],report=json.loads(row['report']),artifact_sha256=row['artifact_sha256'])


def require_release(conn, rid):
    row = conn.execute('SELECT * FROM ml_releases WHERE id=?',(rid,)).fetchone()
    if not row: raise HTTPException(404,'Paket model tidak ditemukan.')
    return row


def register_model_routes(app,db,clock,supervisor):
    def replay(conn,payload,user):
        row = conn.execute('SELECT * FROM ml_releases WHERE request_key=?',(payload.request_key,)).fetchone()
        if not row: return None
        if row['run_id']!=payload.run_id or row['actor_id']!=user['id']: raise HTTPException(409,'Kunci training dipakai untuk sumber/akun berbeda.')
        return dict(**public_release(row),replayed=True)

    @app.get('/api/models/serving')
    def current(user=Depends(supervisor)):
        with db.connect() as conn:
            state = serving_state(conn)
            state['mode']='ml_simulation' if state['release_id'] else 'rules'
            state['status']='ready'
            if state['release_id']:
                try: valid_artifact(require_release(conn,state['release_id']))
                except (ValueError,KeyError,TypeError,HTTPException): state['status']='invalid_fallback'
            state['history']=[dict(json.loads(r['result']),created_at=r['created_at']) for r in conn.execute('SELECT * FROM ml_transitions ORDER BY created_at DESC,request_key DESC LIMIT 20')]
            return state

    @app.get('/api/models')
    def registry(offset: int=Query(0,ge=0),limit: int=Query(20,ge=1,le=100),user=Depends(supervisor)):
        with db.connect() as conn:
            return dict(total=conn.execute('SELECT COUNT(*) FROM ml_releases').fetchone()[0],
                items=[public_release(r) for r in conn.execute('SELECT * FROM ml_releases ORDER BY created_at DESC,id DESC LIMIT ? OFFSET ?',(limit,offset))])

    @app.post('/api/models/train',status_code=201)
    def train(payload: TrainInput,user=Depends(supervisor)):
        with db.connect() as conn:
            existing=replay(conn,payload,user)
            if existing:return existing
            run=require_run(conn,payload.run_id); manifest=json.loads(run['manifest'])
            if manifest['feature_version']!=FEATURE_VERSION or manifest['simulator_version']!=VERSION:
                raise HTTPException(422,'Versi dataset belum didukung trainer.')
            bundle={n:[json.loads(r[0]) for r in conn.execute('SELECT payload FROM analytics_'+n+' WHERE run_id=? ORDER BY record_id',(payload.run_id,))] for n in ('cases','decisions','events','samples')}
        try:
            if content_hash(bundle)!=run['data_sha256']: raise ValueError('Hash dataset tidak cocok.')
            config=HistoryConfig(**json.loads(run['config']))
            validate_bundle({k:v for k,v in bundle.items() if k!='samples'},bundle['samples'],config)
            artifact,report=train_release(bundle['samples'],dict(run_id=run['id'],data_sha256=run['data_sha256'],collection_hours=72,origination_days=config.origination_window_days))
        except ValueError as exc: raise HTTPException(422,str(exc))
        row=dict(id='MOD-'+uuid4().hex[:12].upper(),request_key=payload.request_key,run_id=payload.run_id,
            actor_id=user['id'],created_at=timestamp(clock()),report=encode(report),artifact=encode(artifact),artifact_sha256=content_hash(artifact))
        with db.connect(write=True) as conn:
            existing=replay(conn,payload,user)
            if existing:return existing
            conn.execute('INSERT INTO ml_releases(id,request_key,run_id,actor_id,created_at,report,artifact,artifact_sha256) VALUES (?,?,?,?,?,?,?,?)',tuple(row.values()))
            audit(conn,user,'model_train',None,dict(release_id=row['id'],run_id=payload.run_id,artifact_sha256=row['artifact_sha256']),clock())
        return dict(**public_release(row),replayed=False)

    @app.post('/api/models/serving')
    def switch(payload: ServingInput,user=Depends(supervisor)):
        body=encode(payload.model_dump(exclude={'request_key'}))
        with db.connect(write=True) as conn:
            prior=conn.execute('SELECT * FROM ml_transitions WHERE request_key=?',(payload.request_key,)).fetchone()
            if prior:
                if prior['actor_id']!=user['id'] or prior['payload']!=body: raise HTTPException(409,'Kunci perubahan dipakai untuk tindakan berbeda.')
                return dict(json.loads(prior['result']),replayed=True)
            before=serving_state(conn)
            if before['revision']!=payload.expected_revision: raise HTTPException(409,'Model aktif berubah. Muat versi serving terbaru.')
            if payload.release_id:
                row=require_release(conn,payload.release_id)
                try: valid_artifact(row)
                except (ValueError,KeyError,TypeError): raise HTTPException(409,'Artefak model tidak valid; aktivasi ditolak.')
                if not json.loads(row['report'])['activation_eligible']: raise HTTPException(409,'Paket tidak memenuhi pemeriksaan demo.')
            result=dict(release_id=payload.release_id,previous_release_id=before['release_id'],revision=before['revision']+1,
                updated_at=timestamp(clock()),reason=payload.reason)
            if before['revision']==0:
                conn.execute('INSERT INTO ml_serving(id,release_id,revision,updated_at) VALUES (?,?,?,?)',('default',result['release_id'],result['revision'],result['updated_at']))
            else: conn.execute("UPDATE ml_serving SET release_id=?,revision=?,updated_at=? WHERE id='default'",(result['release_id'],result['revision'],result['updated_at']))
            conn.execute('INSERT INTO ml_transitions(request_key,actor_id,payload,result,created_at) VALUES (?,?,?,?,?)',(payload.request_key,user['id'],body,encode(result),timestamp(clock())))
            audit(conn,user,'model_serving_change',None,result,clock())
            return dict(result,replayed=False)

    @app.get('/api/models/{release_id}')
    def detail(release_id: str,user=Depends(supervisor)):
        with db.connect() as conn:return public_release(require_release(conn,release_id))

    @app.get('/api/models/{release_id}/export')
    def export(release_id: str,user=Depends(supervisor)):
        with db.connect() as conn:row=dict(require_release(conn,release_id))
        try: valid_artifact(row)
        except (ValueError,KeyError,TypeError): raise HTTPException(409,'Checksum model tidak cocok; unduhan diblokir.')
        stream=io.BytesIO()
        with zipfile.ZipFile(stream,'w') as z:
            for name,content in {'model.json':row['artifact'],'report.json':encode(public_release(row))}.items():
                info=zipfile.ZipInfo(name,(1980,1,1,0,0,0));info.compress_type=zipfile.ZIP_DEFLATED;z.writestr(info,content)
        with db.connect(write=True) as conn:audit(conn,user,'model_export',None,dict(release_id=release_id),clock())
        return Response(stream.getvalue(),media_type='application/zip',headers={'Content-Disposition':f'attachment; filename="{row["id"]}-model-demo.zip"'})
