"""Local inbox, mock adapters and account controls. Never sends external messages."""
import json
from datetime import timedelta
from typing import Literal
from uuid import uuid4
from fastapi import Depends,HTTPException,Query
from pydantic import Field,model_validator
from .schemas import Input
from .domain import TERMINAL,timestamp
from .historical import encode
from .security import password_hash,verify_password
from .service import audit,require_case
from .operation_events import notify,account_active,agent_account_active

class RequestKey(Input):
    request_key:str=Field(min_length=16,max_length=100)
class EnqueueInput(RequestKey):
    channel:Literal['telephony','omnichannel']
    scenario:Literal['success','fail_once','fail_always']='success'
    expected_version:int=Field(ge=1,strict=True)
class ProcessInput(RequestKey):
    limit:int=Field(default=20,ge=1,le=50,strict=True)
class RetryInput(RequestKey):
    expected_version:int=Field(ge=1,strict=True)
    scenario:Literal['success','fail_once','fail_always']
    reason:str=Field(min_length=10,max_length=500)
class AccountInput(RequestKey):
    expected_version:int=Field(ge=0,strict=True)
    active:bool
    new_password:str|None=Field(default=None,min_length=12,max_length=128)
    reason:str=Field(min_length=10,max_length=500)

def replay(c,payload,user,operation,body,password=None):
    row=c.execute('SELECT * FROM operation_requests WHERE request_key=?',(payload.request_key,)).fetchone()
    if not row:return None
    same=row['actor_id']==user['id'] and row['operation']==operation and row['payload']==encode(body)
    if password is not None:same=same and bool(row['secret_hash']) and verify_password(password,row['secret_hash'])
    if not same:raise HTTPException(409,'Kunci operasi dipakai untuk payload/akun berbeda.')
    return dict(json.loads(row['result']),replayed=True)

def remember(c,payload,user,operation,body,result,now,secret=None):
    c.execute('INSERT INTO operation_requests(request_key,actor_id,operation,payload,result,created_at,secret_hash) VALUES (?,?,?,?,?,?,?)',
        (payload.request_key,user['id'],operation,encode(body),encode(result),timestamp(now),secret))

def job_detail(c,row):
    return dict(row)|dict(attempt_history=[dict(r) for r in c.execute('SELECT * FROM integration_attempts WHERE job_id=? ORDER BY attempt',(row['id'],))],mode='simulation-only')

def job_for_user(c,jid,user):
    row=c.execute('SELECT * FROM integration_jobs WHERE id=?',(jid,)).fetchone()
    if not row:raise HTTPException(404,'Job simulasi tidak ditemukan.')
    require_case(c,row['case_id'],user)
    return row

def job_event(c,job,title,now):
    recipients={job['actor_id']}
    case=c.execute('SELECT agent_id FROM cases WHERE id=?',(job['case_id'],)).fetchone()
    if case:recipients.update(r['id'] for r in c.execute('SELECT id FROM users WHERE agent_id=?',(case['agent_id'],)))
    for uid in recipients:
        notify(c,uid,f'job:{job["id"]}:{job["version"]}:{uid}',job['case_id'],title,
            f'{job["channel"]} simulasi: {job["state"]}. Tidak mengirim pesan atau menelepon pihak luar.',now)

def register_operation_routes(app,db,clock,current_user,supervisor):
    @app.get('/api/notifications')
    def inbox(unread:bool=False,offset:int=Query(0,ge=0),limit:int=Query(25,ge=1,le=100),user=Depends(current_user)):
        with db.connect() as c:
            where=' WHERE user_id=?'+(' AND read_at IS NULL' if unread else '')
            total=c.execute('SELECT count(*) FROM notifications'+where,(user['id'],)).fetchone()[0]
            count=c.execute('SELECT count(*) FROM notifications WHERE user_id=? AND read_at IS NULL',(user['id'],)).fetchone()[0]
            items=[]
            for row in c.execute('SELECT * FROM notifications'+where+' ORDER BY created_at DESC,id DESC LIMIT ? OFFSET ?',(user['id'],limit,offset)):
                case=c.execute('SELECT agent_id FROM cases WHERE id=?',(row['case_id'],)).fetchone()
                items.append(dict(row)|dict(can_open=bool(case and (user['role']=='supervisor' or case['agent_id']==user['agent_id']))))
            return dict(items=items,total=total,unread=count,offset=offset,limit=limit)

    @app.patch('/api/notifications/{nid}/read')
    def mark_read(nid:str,user=Depends(current_user)):
        with db.connect(write=True) as c:
            row=c.execute('SELECT * FROM notifications WHERE id=? AND user_id=?',(nid,user['id'])).fetchone()
            if not row:raise HTTPException(404,'Notifikasi tidak ditemukan.')
            when=row['read_at'] or timestamp(clock())
            if row['read_at'] is None:c.execute('UPDATE notifications SET read_at=? WHERE id=?',(when,nid))
            return dict(id=nid,read_at=when)

    @app.post('/api/notifications/scan')
    def scan(payload:RequestKey,user=Depends(supervisor)):
        with db.connect(write=True) as c:
            saved=replay(c,payload,user,'sla_scan',{})
            if saved:return saved
            created=0
            for case in c.execute("SELECT * FROM cases WHERE agent_id IS NOT NULL AND due_at<? AND status NOT IN ('paid','disbursed','rejected')",(timestamp(clock()),)):
                for row in c.execute('SELECT id FROM users WHERE agent_id=?',(case['agent_id'],)):
                    if not account_active(c,row['id']):continue
                    key=f'sla:{case["id"]}:{case["cycle"]}:{row["id"]}'
                    if not c.execute('SELECT 1 FROM notifications WHERE event_key=?',(key,)).fetchone():
                        notify(c,row['id'],key,case['id'],'Tindak lanjut melewati SLA','Periksa kasus dan catat tindak lanjut. Pengingat tidak mengubah outcome assignment.',clock());created+=1
            result=dict(created=created)
            audit(c,user,'sla_scan',None,result,clock());remember(c,payload,user,'sla_scan',{},result,clock());return dict(result,replayed=False)

    @app.post('/api/cases/{cid}/integrations',status_code=201)
    def enqueue(cid:str,payload:EnqueueInput,user=Depends(current_user)):
        body=dict(case_id=cid,**payload.model_dump(exclude={'request_key'}))
        with db.connect(write=True) as c:
            case=require_case(c,cid,user)
            saved=replay(c,payload,user,'enqueue',body)
            if saved:return dict(job=job_detail(c,job_for_user(c,saved['job_id'],user)),replayed=True)
            if user['role']!='supervisor' and payload.scenario!='success':raise HTTPException(403,'Skenario gangguan hanya untuk supervisor.')
            if case['version']!=payload.expected_version:raise HTTPException(409,'Kasus berubah. Muat ulang sebelum membuat job.')
            if case['status'] in TERMINAL or not case['agent_id']:raise HTTPException(409,'Job tindak lanjut hanya untuk assignment aktif.')
            jid='JOB-'+uuid4().hex[:16].upper();when=timestamp(clock())
            c.execute('INSERT INTO integration_jobs(id,request_key,actor_id,case_id,cycle,channel,scenario,state,attempts,attempt_limit,version,available_at,created_at,updated_at,receipt_id) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
                (jid,payload.request_key,user['id'],cid,case['cycle'],payload.channel,payload.scenario,'pending',0,3,1,when,when,when,None))
            result=dict(job_id=jid);audit(c,user,'integration_enqueue',cid,dict(job_id=jid,channel=payload.channel,scenario=payload.scenario,mode='simulation-only'),clock())
            remember(c,payload,user,'enqueue',body,result,clock())
            return dict(job=job_detail(c,c.execute('SELECT * FROM integration_jobs WHERE id=?',(jid,)).fetchone()),replayed=False)

    @app.get('/api/integrations')
    def jobs(offset:int=Query(0,ge=0),limit:int=Query(25,ge=1,le=100),user=Depends(current_user)):
        where='' if user['role']=='supervisor' else ' WHERE c.agent_id=?'
        args=[] if user['role']=='supervisor' else [user['agent_id']]
        sql=' FROM integration_jobs j JOIN cases c ON c.id=j.case_id'
        with db.connect() as c:
            total=c.execute('SELECT count(*)'+sql+where,args).fetchone()[0]
            rows=c.execute('SELECT j.*'+sql+where+' ORDER BY j.created_at DESC,j.id DESC LIMIT ? OFFSET ?',[*args,limit,offset])
            return dict(items=[job_detail(c,r) for r in rows],total=total,offset=offset,limit=limit,mode='simulation-only')

    @app.post('/api/integrations/process')
    def process(payload:ProcessInput,user=Depends(supervisor)):
        body=payload.model_dump(exclude={'request_key'})
        with db.connect(write=True) as c:
            saved=replay(c,payload,user,'process',body)
            if saved:return saved
            now=clock();when=timestamp(now);results=[]
            rows=[dict(r) for r in c.execute("SELECT * FROM integration_jobs WHERE state IN ('pending','retry') AND available_at<=? ORDER BY available_at,id LIMIT ?",(when,payload.limit))]
            for job in rows:
                case=c.execute('SELECT * FROM cases WHERE id=?',(job['case_id'],)).fetchone();attempt=job['attempts']+1
                invalid=not case or case['status'] in TERMINAL or case['cycle']!=job['cycle'] or not account_active(c,job['actor_id']) or not agent_account_active(c,case['agent_id'])
                failed=job['scenario']=='fail_always' or (job['scenario']=='fail_once' and job['attempts']==0)
                state='canceled' if invalid else ('dead' if attempt>=job['attempt_limit'] else 'retry') if failed else 'delivered'
                detail='Assignment/scope/akun tidak lagi aktif; adapter tidak dijalankan.' if invalid else 'Gangguan adapter tiruan; tidak ada permintaan eksternal.' if failed else 'Receipt lokal mock-v1; tidak ada panggilan/pesan keluar.'
                receipt='MOCK-'+job['id'] if state=='delivered' else None
                available=timestamp(now+timedelta(seconds=min(300,15*2**min(attempt-1,4)))) if state=='retry' else when
                c.execute('UPDATE integration_jobs SET state=?,attempts=?,version=version+1,available_at=?,updated_at=?,receipt_id=? WHERE id=?',(state,attempt,available,when,receipt,job['id']))
                c.execute('INSERT INTO integration_attempts(job_id,attempt,state,detail,created_at) VALUES (?,?,?,?,?)',(job['id'],attempt,state,detail,when))
                current=c.execute('SELECT * FROM integration_jobs WHERE id=?',(job['id'],)).fetchone();job_event(c,current,'Hasil integrasi simulasi',now)
                results.append(dict(job_id=job['id'],state=state,attempt=attempt,receipt_id=receipt));audit(c,user,'integration_attempt',job['case_id'],results[-1],now)
            result=dict(processed=len(results),results=results,mode='simulation-only')
            remember(c,payload,user,'process',body,result,now);return dict(result,replayed=False)

    @app.post('/api/integrations/{jid}/retry')
    def retry(jid:str,payload:RetryInput,user=Depends(supervisor)):
        body=dict(job_id=jid,**payload.model_dump(exclude={'request_key'}))
        with db.connect(write=True) as c:
            saved=replay(c,payload,user,'retry',body)
            if saved:return saved
            job=job_for_user(c,jid,user)
            if job['version']!=payload.expected_version:raise HTTPException(409,'Job berubah. Muat versi terbaru.')
            if job['state'] not in {'retry','dead'}:raise HTTPException(409,'Hanya job gagal/retry dapat dijadwalkan ulang.')
            case=require_case(c,job['case_id'],user)
            if case['status'] in TERMINAL or case['cycle']!=job['cycle']:raise HTTPException(409,'Assignment sudah berakhir/berubah; buat job baru pada siklus aktif.')
            c.execute("UPDATE integration_jobs SET state='pending',scenario=?,attempt_limit=?,available_at=?,updated_at=?,version=version+1 WHERE id=?",(payload.scenario,job['attempts']+3,timestamp(clock()),timestamp(clock()),jid))
            result=dict(job_id=jid,version=job['version']+1);audit(c,user,'integration_retry',job['case_id'],dict(**result,reason=payload.reason,scenario=payload.scenario),clock())
            remember(c,payload,user,'retry',body,result,clock());return dict(result,replayed=False)

    @app.get('/api/accounts')
    def accounts(user=Depends(supervisor)):
        with db.connect() as c:
            rows=c.execute("SELECT u.id,u.username,u.agent_id,g.name,COALESCE(a.active,1) active,COALESCE(a.version,0) version FROM users u JOIN agents g ON g.id=u.agent_id LEFT JOIN user_controls a ON a.user_id=u.id WHERE u.role='agent' ORDER BY u.username LIMIT 200")
            return dict(items=[dict(r)|dict(active_cases=c.execute("SELECT count(*) FROM cases WHERE agent_id=? AND status NOT IN ('paid','disbursed','rejected')",(r['agent_id'],)).fetchone()[0]) for r in rows])

    @app.patch('/api/accounts/{uid}')
    def account(uid:str,payload:AccountInput,user=Depends(supervisor)):
        body=dict(user_id=uid,**payload.model_dump(exclude={'request_key','new_password'}),password_changed=payload.new_password is not None)
        with db.connect(write=True) as c:
            saved=replay(c,payload,user,'account',body,payload.new_password)
            if saved:return saved
            row=c.execute("SELECT * FROM users WHERE id=? AND role='agent'",(uid,)).fetchone()
            if not row:raise HTTPException(404,'Akun petugas tidak ditemukan; akun supervisor tidak diedit di sini.')
            control=c.execute('SELECT * FROM user_controls WHERE user_id=?',(uid,)).fetchone();version=control['version'] if control else 0
            if version!=payload.expected_version:raise HTTPException(409,'Akun berubah. Muat versi terbaru.')
            hashed=password_hash(payload.new_password) if payload.new_password is not None else None
            if hashed:c.execute('UPDATE users SET password_hash=? WHERE id=?',(hashed,uid))
            if control:c.execute('UPDATE user_controls SET active=?,version=?,updated_at=? WHERE user_id=?',(int(payload.active),version+1,timestamp(clock()),uid))
            else:c.execute('INSERT INTO user_controls(user_id,active,version,updated_at) VALUES (?,?,?,?)',(uid,int(payload.active),1,timestamp(clock())))
            if hashed or not payload.active:c.execute('DELETE FROM sessions WHERE user_id=?',(uid,))
            result=dict(user_id=uid,active=payload.active,version=version+1,password_changed=hashed is not None)
            audit(c,user,'account_update',None,dict(**result,reason=payload.reason),clock());remember(c,payload,user,'account',body,result,clock(),hashed)
            return dict(result,replayed=False)
