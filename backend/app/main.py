import os
import secrets
from contextlib import asynccontextmanager
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Annotated
from uuid import uuid4

from fastapi import Depends, FastAPI, HTTPException, Query, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import Response
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from fastapi.staticfiles import StaticFiles
from sqlalchemy.exc import SQLAlchemyError

from .db import Database
from .domain import MODEL_VERSION, TERMINAL, score_case, target_team, timestamp
from .schemas import ActivityInput, AgentUpdate, AssignRequest, CaseCreate, Kind, Login, ReassignRequest
from .security import token_hash, verify_password, password_hash
from . import login_guard
from .seed import seed_demo
from .reports import ReportFilter, csv_content, report_filters, report_result, report_rows
from .imports import register_import_routes
from .master import agent_rules, agent_scopes, register_master_routes
from .analytics import register_analytics_routes
from .models import register_model_routes
from .decisions import register_decision_routes
from .policy import current_policy,rule_version
from .operation_events import account_active
from .operations import register_operation_routes
from .scoring import assignment_preview, capture_origin, recorded_prediction, serving_state
import json
from .service import add_activity, agent_load, assign_one, audit, recommendations, reassign, require_case


def create_app(db_path=None, clock=None, seed=True, web_path=None):
    db = Database(db_path or os.getenv('DATABASE_URL') or os.getenv('DATABASE_PATH', str(Path(__file__).resolve().parents[2] / 'runtime' / 'assignment.db')))
    clock = clock or (lambda: datetime.now(timezone.utc))

    @asynccontextmanager
    async def lifespan(app):
        db.initialize()
        if seed:
            seed_demo(db, clock())
        yield
        db.dispose()

    app = FastAPI(title='Assignment Studio · Prototype API', version='0.13.0', lifespan=lifespan)
    app.state.db = db
    app.add_middleware(CORSMiddleware, allow_origins=['http://localhost:5173', 'http://127.0.0.1:5173'],
                       allow_methods=['GET', 'POST', 'PATCH'], allow_headers=['Authorization', 'Content-Type'])
    bearer = HTTPBearer(auto_error=False)

    @app.middleware('http')
    async def prevent_private_response_cache(request, call_next):
        response = await call_next(request)
        response.headers['Cache-Control'] = 'no-store'
        response.headers['X-Content-Type-Options'] = 'nosniff'
        response.headers['Referrer-Policy'] = 'no-referrer'
        response.headers['X-Frame-Options'] = 'SAMEORIGIN'
        return response

    def current_user(credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer)]):
        if credentials is None:
            raise HTTPException(401, 'Silakan masuk.', headers={'WWW-Authenticate': 'Bearer'})
        with db.connect() as conn:
            user = conn.execute('SELECT u.* FROM users u JOIN sessions s ON s.user_id=u.id WHERE s.token_hash=? AND s.expires_at>?',
                                (token_hash(credentials.credentials), timestamp(clock()))).fetchone()
            if user is None or not account_active(conn,user['id']):
                raise HTTPException(401, 'Sesi habis. Silakan masuk kembali.', headers={'WWW-Authenticate': 'Bearer'})
            return {k: user[k] for k in ('id', 'username', 'role', 'agent_id')}

    def supervisor(user=Depends(current_user)):
        if user['role'] != 'supervisor':
            raise HTTPException(403, 'Tindakan ini memerlukan supervisor.')
        return user

    def scope(user, kind=None, status=None, q=None):
        terms, args = [], []
        if user['role'] != 'supervisor':
            terms.append('agent_id=?'); args.append(user['agent_id'])
        if kind:
            terms.append('kind=?'); args.append(kind)
        if status:
            terms.append('status=?'); args.append(status)
        if q and q.strip():
            # Search is literal substring matching, including region codes.
            escaped = q.strip().replace('\\', '\\\\').replace('%', '\\%').replace('_', '\\_')
            pattern = f'%{escaped}%'
            terms.append("(customer LIKE ? ESCAPE '\\' OR id LIKE ? ESCAPE '\\' OR region_id LIKE ? ESCAPE '\\')")
            args.extend([pattern, pattern, pattern])
        return (' WHERE ' + ' AND '.join(terms)) if terms else '', args

    @app.get('/api/health')
    def health():
        try:
            with db.connect() as conn: conn.execute('SELECT 1').fetchone()
        except SQLAlchemyError:
            raise HTTPException(503, 'Penyimpanan belum terhubung.')
        return dict(status='ok', version='0.13.0', mode='synthetic-demo', storage=db.engine.dialect.name)

    # Same PBKDF work for unknown/inactive users; generated once, never a credential.
    dummy_hash=password_hash(secrets.token_urlsafe(32))
    @app.post('/api/auth/login')
    def login(payload: Login, request: Request):
        peer=request.client.host if request.client else 'unknown'
        result=None
        with db.connect(write=True) as conn:
            retry,rows=login_guard.check(conn,peer,payload.username,clock())
            if not retry:
                user = conn.execute('SELECT * FROM users WHERE username=?', (payload.username,)).fetchone()
                valid=verify_password(payload.password,user['password_hash'] if user else dummy_hash)
                if user is not None and valid and account_active(conn,user['id']):
                    login_guard.success(conn,peer,payload.username)
                    token = secrets.token_urlsafe(32)
                    conn.execute('DELETE FROM sessions WHERE expires_at<=?', (timestamp(clock()),))
                    conn.execute('INSERT INTO sessions VALUES (?,?,?)', (token_hash(token), user['id'], timestamp(clock()+timedelta(hours=8))))
                    result=dict(access_token=token, token_type='bearer', user={k: user[k] for k in ('id', 'username', 'role', 'agent_id')})
                else:login_guard.failure(conn,rows,clock())
        # Raise only after commit so rejected attempts cannot roll back their budget.
        if retry:raise HTTPException(429,'Terlalu banyak percobaan login. Coba lagi dalam 15 menit.',headers={'Retry-After':str(retry)})
        if result is None:raise HTTPException(401,'Username atau password tidak cocok.',headers={'WWW-Authenticate':'Bearer'})
        return result

    @app.post('/api/auth/logout')
    def logout(credentials: Annotated[HTTPAuthorizationCredentials, Depends(bearer)], user=Depends(current_user)):
        with db.connect(write=True) as conn:
            conn.execute('DELETE FROM sessions WHERE token_hash=?', (token_hash(credentials.credentials),))
        return dict(ok=True)

    @app.get('/api/me')
    def me(user=Depends(current_user)):
        return user

    @app.get('/api/config')
    def config(user=Depends(current_user)):
        with db.connect() as conn:
            mode='mixed-ml-simulation' if serving_state(conn)['release_id'] else 'rules-demo'
            policy=current_policy(conn)
            return dict(regions=[dict(r) for r in conn.execute('SELECT * FROM regions WHERE active=1 ORDER BY name')],
                        report_regions=[dict(r) for r in conn.execute('SELECT * FROM regions ORDER BY name')],
                        score_mode=mode, score_version=rule_version(policy['revision']), score_is_probability=False,
                        policy_revision=policy['revision'],medium_threshold=policy['config']['medium_threshold'], team_mapping={'A': 'Tele', 'B': 'Lapangan'},
                        collection_sla_hours=policy['config']['collection_followup_hours'], origination_sla_hours=policy['config']['origination_followup_hours'],collection_success_hours=72,
                        assumptions=['A=Tele dan B=Lapangan adalah asumsi demo.', 'Skor 0–100 adalah indeks simulasi, bukan probabilitas.',
                                     'Lunas berarti seluruh nilai tagihan kasus.', 'SLA tindak lanjut mengikuti kebijakan; success penagihan tetap72jam.'])

    @app.get('/api/dashboard')
    def dashboard(user=Depends(current_user)):
        where, args = scope(user)
        with db.connect() as conn:
            cases = [dict(r) for r in conn.execute('SELECT * FROM cases' + where, args)]
            now = timestamp(clock())
            result = {}
            for kind in ('collection', 'origination'):
                rows = [r for r in cases if r['kind'] == kind]
                result[kind] = dict(total=len(rows), unassigned=sum(r['agent_id'] is None for r in rows),
                                    active=sum(r['agent_id'] is not None and r['status'] not in TERMINAL for r in rows),
                                    completed=sum(r['status'] in {'paid', 'disbursed'} for r in rows),
                                    overdue=sum(bool(r['due_at'] and r['due_at'] < now and r['status'] not in TERMINAL) for r in rows),
                                    amount=sum(r['amount'] for r in rows), realized=sum(r['paid'] for r in rows))
            mode='mixed-ml-simulation' if serving_state(conn)['release_id'] else 'rules-demo'
            return dict(streams=result, source='synthetic', score_mode=mode, updated_at=now)

    @app.get('/api/cases')
    def list_cases(kind: Kind | None = None, status: str | None = None, q: str | None = Query(default=None, max_length=100),
                   offset: int = Query(default=0, ge=0), limit: int = Query(default=50, ge=1, le=200), user=Depends(current_user)):
        where, args = scope(user, kind, status, q)
        with db.connect() as conn:
            total = conn.execute('SELECT COUNT(*) FROM cases' + where, args).fetchone()[0]
            rows = conn.execute('SELECT * FROM cases' + where + ' ORDER BY score DESC,id LIMIT ? OFFSET ?', [*args, limit, offset])
            return dict(items=[dict(r) for r in rows], total=total, offset=offset, limit=limit)

    @app.post('/api/cases', status_code=201)
    def create_case(payload: CaseCreate, user=Depends(supervisor)):
        with db.connect(write=True) as conn:
            if not conn.execute('SELECT 1 FROM regions WHERE id=? AND active=1', (payload.region_id,)).fetchone():
                raise HTTPException(422, 'Wilayah tidak dikenal atau nonaktif.')
            case = payload.model_dump()
            case['documents_complete'] = int(case['documents_complete'])
            case.update(id=f'{"TAG" if payload.kind == "collection" else "AJU"}-{uuid4().hex[:10].upper()}',
                        created_at=timestamp(clock()), score_version=MODEL_VERSION, source='demo-manual')
            policy=current_policy(conn)
            case['score'] = score_case(case,policy=policy['config'])[0]
            case['score_version']=rule_version(policy['revision'])
            conn.execute(f'INSERT INTO cases ({",".join(case)}) VALUES ({",".join("?" for _ in case)})', tuple(case.values()))
            capture_origin(conn,case)
            audit(conn, user, 'create', case['id'], dict(kind=payload.kind), clock())
            return dict(conn.execute('SELECT * FROM cases WHERE id=?', (case['id'],)).fetchone())

    @app.get('/api/cases/{case_id}')
    def detail(case_id: str, user=Depends(current_user)):
        with db.connect() as conn:
            case = require_case(conn, case_id, user)
            assignments = [dict(r) for r in conn.execute('SELECT * FROM assignments WHERE case_id=? ORDER BY cycle', (case_id,))]
            activities = [dict(r) for r in conn.execute('SELECT * FROM activities WHERE case_id=? ORDER BY id DESC', (case_id,))]
            for a in assignments:
                row=conn.execute('SELECT payload FROM ml_predictions WHERE case_id=? AND cycle=?',(case_id,a['cycle'])).fetchone()
                a['prediction']=json.loads(row[0]) if row else None
            proposed=case
            prediction=recorded_prediction(conn,case)
            if prediction and prediction.get('policy'):proposed={**case,'medium_threshold':prediction['policy']['config']['medium_threshold']}
            if not case['agent_id'] and case['status'] not in TERMINAL: proposed,prediction=assignment_preview(conn,case,clock())
            return dict(case=case, assignments=assignments, activities=activities, target_team=target_team(proposed),prediction=prediction,
                        recommendations=recommendations(conn, proposed, clock()) if user['role']=='supervisor' else [])

    @app.post('/api/assignments')
    def assign(payload: AssignRequest, user=Depends(supervisor)):
        with db.connect(write=True) as conn:
            cases = [require_case(conn, cid, user) for cid in payload.case_ids]
            cases.sort(key=lambda c: (-(assignment_preview(conn,c,clock())[0]['score'] if c['agent_id'] is None and c['status'] not in TERMINAL else c['score']), c['id']))
            return dict(results=[assign_one(conn, case, user, clock()) for case in cases])

    @app.post('/api/cases/{case_id}/reassign')
    def reassign_case(case_id: str, payload: ReassignRequest, user=Depends(supervisor)):
        with db.connect(write=True) as conn:
            return reassign(conn, require_case(conn, case_id, user), user, payload, clock())

    @app.post('/api/cases/{case_id}/activities')
    def activity(case_id: str, payload: ActivityInput, user=Depends(current_user)):
        with db.connect(write=True) as conn:
            return add_activity(conn, require_case(conn, case_id, user), user, payload, clock())

    @app.get('/api/agents')
    def agents(user=Depends(supervisor)):
        with db.connect() as conn:
            result = []
            for r in conn.execute('SELECT * FROM agents ORDER BY kind,region_id,team'):
                agent = dict(r)
                agent['daily_load'], agent['active_load'] = agent_load(conn, agent['id'], clock())
                account = conn.execute('SELECT username FROM users WHERE agent_id=?', (agent['id'],)).fetchone()
                agent['username'] = account['username'] if account else None
                agent['report_scopes'] = agent_scopes(conn, agent)
                result.append(agent)
            return result

    @app.patch('/api/agents/{agent_id}')
    def update_agent(agent_id: str, payload: AgentUpdate, user=Depends(supervisor)):
        with db.connect(write=True) as conn:
            old = conn.execute('SELECT * FROM agents WHERE id=?', (agent_id,)).fetchone()
            if not old:
                raise HTTPException(404, 'Petugas tidak ditemukan.')
            if payload.expected_version is not None and old['version'] != payload.expected_version:
                raise HTTPException(409, 'Profil petugas berubah. Muat ulang master.')
            agent_rules(conn, {**dict(old), 'capacity': payload.capacity, 'active': payload.active}, clock(), old)
            conn.execute('UPDATE agents SET capacity=?,active=?,version=version+1 WHERE id=?', (payload.capacity, int(payload.active), agent_id))
            audit(conn, user, 'update_agent', None, dict(agent_id=agent_id, before=dict(old), **payload.model_dump()), clock())
            return dict(ok=True)

    @app.get('/api/audit')
    def audit_log(user=Depends(supervisor)):
        with db.connect() as conn:
            return [dict(r) for r in conn.execute('SELECT * FROM audit ORDER BY id DESC LIMIT 100')]

    @app.get('/api/reports')
    def report_preview(filters: Annotated[ReportFilter, Depends(report_filters)],
                       offset: int = Query(0, ge=0), limit: int = Query(25, ge=1, le=200), user=Depends(supervisor)):
        now = clock()
        with db.connect() as conn:
            conn.execute('BEGIN')  # Consistent read snapshot across filter validation and rows.
            rows = report_rows(conn, filters, now)
            return report_result(rows, filters, now, offset, limit)

    @app.get('/api/reports/export')
    def report_export(filters: Annotated[ReportFilter, Depends(report_filters)], user=Depends(supervisor)):
        now = clock()
        with db.connect(write=True) as conn:
            rows = report_rows(conn, filters, now)
            content = csv_content(rows, filters, now)
            audit(conn, user, 'export_report', None,
                  dict(filters={k: str(v) if v is not None else None for k, v in vars(filters).items()}, rows=len(rows)), now)
        return Response(content, media_type='text/csv; charset=utf-8',
                        headers={'Content-Disposition': f'attachment; filename="{filters.kind}-{filters.view}-demo.csv"'})

    register_import_routes(app, db, clock, supervisor)
    register_master_routes(app, db, clock, supervisor)
    register_analytics_routes(app, db, clock, supervisor)
    register_model_routes(app, db, clock, supervisor)
    register_decision_routes(app, db, clock, supervisor)
    register_operation_routes(app, db, clock, current_user, supervisor)
    static=web_path or os.getenv('WEB_BUILD_PATH')
    if static:
        root=Path(static).resolve()
        if not (root/'index.html').is_file():raise ValueError('WEB_BUILD_PATH must contain a compiled web/index.html.')
        app.mount('/',StaticFiles(directory=root,html=True),name='web')
    return app


app = create_app()
