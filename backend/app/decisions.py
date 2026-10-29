"""Supervisor policy review, immutable segmentation and audited publication."""
import json
from uuid import uuid4
from fastapi import Depends,HTTPException
from pydantic import Field
from .schemas import Input
from .policy import PolicyConfig,current_policy
from .historical import content_hash,encode
from .segments import FORMAT,train_segments
from .scoring import valid_artifact
from .models import require_release
from .service import audit
from .domain import timestamp

class PolicyInput(Input):
    config: PolicyConfig
    expected_revision: int = Field(ge=0,strict=True)
    request_key: str = Field(min_length=16,max_length=100)
    reason: str = Field(min_length=10,max_length=500)

class SegmentInput(Input):
    model_id: str = Field(min_length=5,max_length=64)
    request_key: str = Field(min_length=16,max_length=100)

def public_segment(row):
    return {k:row[k] for k in ('id','model_id','created_at','artifact_sha256')}|dict(report=json.loads(row['report']))

def register_decision_routes(app,db,clock,supervisor):
    @app.get('/api/decisions')
    def overview(user=Depends(supervisor)):
        with db.connect() as c:
            policy=current_policy(c)
            rows=[dict(r) for r in c.execute('SELECT * FROM segment_releases ORDER BY created_at DESC,id DESC LIMIT 20')]
            active=policy['config']['segment_release_id']
            if active and all(r['id']!=active for r in rows):
                row=c.execute('SELECT * FROM segment_releases WHERE id=?',(active,)).fetchone()
                if row:rows.append(dict(row))
            return dict(policy=policy,segments=[public_segment(r) for r in rows],model_ids=[r[0] for r in c.execute('SELECT id FROM ml_releases ORDER BY created_at DESC,id DESC LIMIT 100')],
                history=[dict(revision=r['revision'],reason=r['reason'],created_at=r['created_at'],config=json.loads(r['config'])) for r in c.execute('SELECT * FROM policy_revisions ORDER BY revision DESC LIMIT 20')],
                invariants=['Low selalu Tim A; High selalu Tim B.','Keberhasilan penagihan tetap lunas dalam72jam; SLA tindak lanjut terpisah.','Perubahan hanya untuk keputusan baru, bukan backfill histori.'])

    @app.post('/api/decisions/policy')
    def publish(payload:PolicyInput,user=Depends(supervisor)):
        config=encode(payload.config.model_dump())
        with db.connect(write=True) as c:
            old=c.execute('SELECT * FROM policy_revisions WHERE request_key=?',(payload.request_key,)).fetchone()
            if old:
                if old['actor_id']!=user['id'] or old['config']!=config or old['reason']!=payload.reason or old['revision']!=payload.expected_revision+1:raise HTTPException(409,'Kunci kebijakan dipakai untuk perubahan berbeda.')
                return dict(revision=old['revision'],config=json.loads(old['config']),replayed=True)
            before=current_policy(c)
            if before['revision']!=payload.expected_revision:raise HTTPException(409,'Kebijakan berubah. Muat ulang dan tinjau lagi.')
            if payload.config.segment_release_id:
                row=c.execute('SELECT * FROM segment_releases WHERE id=?',(payload.config.segment_release_id,)).fetchone()
                if not row:raise HTTPException(422,'Paket segmen tidak ditemukan.')
                artifact=json.loads(row['artifact'])
                if artifact.get('format')!=FORMAT or content_hash(artifact)!=row['artifact_sha256']:raise HTTPException(409,'Artefak segmen tidak valid.')
            revision=before['revision']+1
            c.execute('INSERT INTO policy_revisions(revision,request_key,actor_id,config,reason,created_at) VALUES (?,?,?,?,?,?)',
                (revision,payload.request_key,user['id'],config,payload.reason,timestamp(clock())))
            audit(c,user,'policy_publish',None,dict(before=before,after=dict(revision=revision,config=payload.config.model_dump()),reason=payload.reason),clock())
            return dict(revision=revision,config=payload.config.model_dump(),replayed=False)

    @app.post('/api/decisions/segments',status_code=201)
    def train(payload:SegmentInput,user=Depends(supervisor)):
        def replay(c):
            old=c.execute('SELECT * FROM segment_releases WHERE request_key=?',(payload.request_key,)).fetchone()
            if old:
                if old['actor_id']!=user['id'] or old['model_id']!=payload.model_id:raise HTTPException(409,'Kunci training segmen dipakai untuk sumber berbeda.')
                return dict(**public_segment(old),replayed=True)
        with db.connect() as c:
            saved=replay(c)
            if saved:return saved
            model=require_release(c,payload.model_id)
            try:source=valid_artifact(model)
            except (ValueError,KeyError,TypeError):raise HTTPException(409,'Model/preprocessing sumber tidak valid.')
            run=c.execute('SELECT * FROM analytics_runs WHERE id=?',(model['run_id'],)).fetchone()
            bundle={n:[json.loads(r[0]) for r in c.execute('SELECT payload FROM analytics_'+n+' WHERE run_id=? ORDER BY record_id',(model['run_id'],))] for n in ('cases','decisions','events','samples')}
            if content_hash(bundle)!=run['data_sha256'] or source['provenance']['data_sha256']!=run['data_sha256']:raise HTTPException(409,'Checksum histori sumber berubah.')
        try:artifact,report=train_segments(source,bundle['samples'])
        except ValueError as exc:raise HTTPException(422,str(exc))
        row=dict(id='SEG-'+uuid4().hex[:12].upper(),request_key=payload.request_key,model_id=payload.model_id,actor_id=user['id'],
            created_at=timestamp(clock()),artifact=encode(artifact),artifact_sha256=content_hash(artifact),report=encode(report))
        with db.connect(write=True) as c:
            saved=replay(c)
            if saved:return saved
            c.execute('INSERT INTO segment_releases(id,request_key,model_id,actor_id,created_at,artifact,artifact_sha256,report) VALUES (?,?,?,?,?,?,?,?)',tuple(row.values()))
            audit(c,user,'segment_train',None,dict(id=row['id'],model_id=payload.model_id,hash=row['artifact_sha256']),clock())
            return dict(**public_segment(row),replayed=False)

    @app.get('/api/decisions/segments/{release_id}')
    def detail(release_id:str,user=Depends(supervisor)):
        with db.connect() as c:
            row=c.execute('SELECT * FROM segment_releases WHERE id=?',(release_id,)).fetchone()
            if not row:raise HTTPException(404,'Segmen tidak ditemukan.')
            return public_segment(row)
