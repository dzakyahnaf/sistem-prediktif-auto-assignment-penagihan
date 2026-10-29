"""Operational master data and explicit assignment, sharing the assignment transaction."""
import json
from uuid import uuid4

from fastapi import Depends, HTTPException

from .domain import TERMINAL, score_case, target_team, timestamp
from .schemas import AgentCreate, AgentEdit, OverrideInput, RegionCreate, RegionEdit
from .security import password_hash
from .service import agent_load, assign_one, audit, reassign, require_case
from .scoring import assignment_preview, serving_state
from .policy import current_policy
from .operation_events import agent_account_active


def agent_scopes(conn, agent):
    scopes = {(agent['kind'], agent['region_id'])}
    scopes.update((r[0], r[1]) for r in conn.execute('''SELECT DISTINCT c.kind,c.region_id FROM cases c
        WHERE c.agent_id=? OR EXISTS (SELECT 1 FROM assignments a WHERE a.case_id=c.id AND a.agent_id=?)''', (agent['id'], agent['id'])))
    return [dict(kind=k, region_id=r) for k, r in sorted(scopes)]


def region_active(conn, rid):
    return conn.execute('SELECT 1 FROM regions WHERE id=? AND active=1', (rid,)).fetchone() is not None


def agent_rules(conn, data, now, old=None):
    if not conn.execute('SELECT 1 FROM regions WHERE id=?', (data['region_id'],)).fetchone():
        raise HTTPException(422, 'Wilayah tidak terdaftar.')
    if data['active'] and not region_active(conn, data['region_id']):
        raise HTTPException(409, 'Petugas aktif memerlukan wilayah aktif.')
    if old:
        daily, active = agent_load(conn, old['id'], now)
        if data['capacity'] < max(daily, active):
            raise HTTPException(409, 'Kapasitas tidak boleh di bawah beban yang sudah berjalan hari ini.')
        routing = ['region_id', 'kind', 'team']
        # Scope and routing cannot change underneath ongoing work, even if inactive.
        if any(data[k] != old[k] for k in routing) and conn.execute(
            "SELECT 1 FROM cases WHERE agent_id=? AND status NOT IN ('paid','disbursed','rejected') LIMIT 1", (old['id'],)).fetchone():
            raise HTTPException(409, 'Petugas masih memegang kasus aktif. Selesaikan atau alihkan tugas sebelum mengubah wilayah, alur, atau tim.')


def check_region_name(conn, rid, name):
    for r in conn.execute('SELECT id,name FROM regions'):
        if r['id'] != rid and (name.casefold() in {r['name'].casefold(), r['id'].casefold()} or rid.casefold() == r['name'].casefold()):
            raise HTTPException(409, 'Kode/nama wilayah harus unik dan tidak bertabrakan dengan kode atau nama wilayah lain.')


def projected_case(conn, case, now):
    if case['agent_id'] and not conn.execute('SELECT 1 FROM assignments WHERE case_id=? AND ended_at IS NULL',(case['id'],)).fetchone():
        raise HTTPException(409,'Siklus aktif tidak ditemukan. Muat ulang kasus.')
    return assignment_preview(conn,case,now,closing_current=bool(case['agent_id']))


def override_options(conn, case, now):
    if case['status'] in TERMINAL:
        raise HTTPException(409, 'Kasus selesai tidak dapat ditugaskan.')
    proposed, prediction = projected_case(conn, case, now)
    team = target_team(proposed)
    options = []
    for row in conn.execute('SELECT * FROM agents ORDER BY name,id'):
        a = dict(row)
        daily, active = agent_load(conn, a['id'], now)
        remaining = max(0, min(a['capacity'] - daily, a['capacity'] - active))
        reasons = []
        if a['region_id'] != case['region_id']: reasons.append('Wilayah berbeda')
        if a['kind'] != case['kind']: reasons.append('Alur berbeda')
        if a['team'] != team: reasons.append(f'Harus Tim {team}')
        if not a['active']: reasons.append('Petugas nonaktif')
        if not agent_account_active(conn,a['id']):reasons.append('Akun petugas nonaktif/tidak tersedia')
        if not region_active(conn, a['region_id']): reasons.append('Wilayah nonaktif')
        if remaining == 0: reasons.append('Kapasitas penuh')
        if a['id'] == case['agent_id']: reasons.append('Petugas saat ini; pilih petugas berbeda')
        options.append(dict(agent_id=a['id'], name=a['name'], region_id=a['region_id'], kind=a['kind'], team=a['team'],
                            channel=a['channel'], daily_load=daily, active_load=active, capacity=a['capacity'], remaining=remaining,
                            eligible=not reasons, reason=' · '.join(reasons) if reasons else 'Cocok dengan aturan dan kapasitas'))
    options.sort(key=lambda a: (not a['eligible'], -a['remaining'], a['agent_id']))
    return dict(case_id=case['id'], expected_version=case['version'], previous_agent=case['agent_id'],
                score=proposed['score'], target_team=team, options=options,prediction=prediction,
                expected_scoring_revision=prediction['serving_revision'],expected_policy_revision=prediction['policy']['revision'])


def perform_override(conn, case_id, payload, user, now):
    body = json.dumps(payload.model_dump(exclude={'request_key'}), sort_keys=True)
    prior = conn.execute('SELECT * FROM assignment_overrides WHERE request_key=?', (payload.request_key,)).fetchone()
    if prior:
        if prior['actor_id'] != user['id'] or prior['case_id'] != case_id or prior['payload'] != body:
            raise HTTPException(409, 'Kunci permintaan sudah dipakai untuk override berbeda.')
        return dict(json.loads(prior['result']), replayed=True)
    case = require_case(conn, case_id, user)
    if payload.expected_policy_revision is not None and current_policy(conn)['revision']!=payload.expected_policy_revision:
        raise HTTPException(409,'Kebijakan berubah. Muat ulang pilihan petugas.')
    if payload.expected_scoring_revision is not None and serving_state(conn)['revision']!=payload.expected_scoring_revision:
        raise HTTPException(409,'Model aktif berubah. Muat ulang pilihan petugas.')
    if case['version'] != payload.expected_version:
        raise HTTPException(409, 'Kasus berubah. Muat ulang dan tinjau pilihan petugas terbaru.')
    options = override_options(conn, case, now)
    chosen = next((a for a in options['options'] if a['agent_id'] == payload.agent_id), None)
    if not chosen or not chosen['eligible']:
        raise HTTPException(409, chosen['reason'] if chosen else 'Petugas tidak ditemukan.')
    result = (reassign(conn, case, user, payload, now, agent_id=payload.agent_id) if case['agent_id']
              else assign_one(conn, case, user, now, payload.reason, agent_id=payload.agent_id))
    if not result['assigned']:
        raise HTTPException(409, result['reason'])
    audit(conn, user, 'override_assignment', case_id, dict(previous_agent=case['agent_id'], agent_id=payload.agent_id,
          reason=payload.reason, previous_score=case['score'], score=options['score'], target_team=options['target_team'], cycle=result['cycle']), now)
    conn.execute('INSERT INTO assignment_overrides VALUES (?,?,?,?,?,?)',
                 (payload.request_key, user['id'], case_id, body, json.dumps(result), timestamp(now)))
    return dict(result, replayed=False)


def register_master_routes(app, db, clock, supervisor):
    @app.get('/api/master/audit')
    def master_audit(user=Depends(supervisor)):
        with db.connect() as conn:
            rows = [dict(r) for r in conn.execute("""SELECT a.*,u.username FROM audit a JOIN users u ON u.id=a.actor_id
                WHERE action IN ('create_region','update_region','create_agent','update_agent_profile','update_agent','override_assignment')
                ORDER BY a.id DESC LIMIT 100""")]
        for row in rows:
            row['detail'] = json.loads(row['detail'])
        return rows

    @app.get('/api/master/regions')
    def regions(user=Depends(supervisor)):
        with db.connect() as conn:
            return [dict(r, case_count=conn.execute('SELECT count(*) FROM cases WHERE region_id=?', (r['id'],)).fetchone()[0],
                         active_cases=conn.execute("SELECT count(*) FROM cases WHERE region_id=? AND status NOT IN ('paid','disbursed','rejected')", (r['id'],)).fetchone()[0],
                         active_agents=conn.execute('SELECT count(*) FROM agents WHERE region_id=? AND active=1', (r['id'],)).fetchone()[0])
                    for r in conn.execute('SELECT * FROM regions ORDER BY name')]

    @app.post('/api/master/regions', status_code=201)
    def create_region(payload: RegionCreate, user=Depends(supervisor)):
        with db.connect(write=True) as conn:
            if conn.execute('SELECT 1 FROM regions WHERE id=?', (payload.id,)).fetchone():
                raise HTTPException(409, 'Kode wilayah sudah ada.')
            if conn.execute('SELECT count(*) FROM regions').fetchone()[0] >= 25:
                raise HTTPException(409, 'Prototype dibatasi 25 wilayah.')
            check_region_name(conn, payload.id, payload.name)
            conn.execute('INSERT INTO regions(id,name,active) VALUES (?,?,?)', (payload.id, payload.name, int(payload.active)))
            audit(conn, user, 'create_region', None, payload.model_dump(), clock())
            return dict(conn.execute('SELECT * FROM regions WHERE id=?', (payload.id,)).fetchone())

    @app.patch('/api/master/regions/{rid}')
    def edit_region(rid: str, payload: RegionEdit, user=Depends(supervisor)):
        with db.connect(write=True) as conn:
            row = conn.execute('SELECT * FROM regions WHERE id=?', (rid,)).fetchone()
            if not row: raise HTTPException(404, 'Wilayah tidak ditemukan.')
            if row['version'] != payload.expected_version: raise HTTPException(409, 'Wilayah berubah. Muat ulang master.')
            check_region_name(conn, rid, payload.name)
            if not payload.active and (conn.execute("SELECT 1 FROM cases WHERE region_id=? AND status NOT IN ('paid','disbursed','rejected') LIMIT 1", (rid,)).fetchone()
                                       or conn.execute('SELECT 1 FROM agents WHERE region_id=? AND active=1 LIMIT 1', (rid,)).fetchone()):
                raise HTTPException(409, 'Wilayah masih memiliki kasus terbuka atau petugas aktif. Selesaikan/alihkan kasus dan nonaktifkan/pindahkan petugas dahulu.')
            conn.execute('UPDATE regions SET name=?,active=?,version=version+1 WHERE id=?', (payload.name, int(payload.active), rid))
            audit(conn, user, 'update_region', None, dict(region_id=rid, before=dict(row), after=payload.model_dump()), clock())
            return dict(conn.execute('SELECT * FROM regions WHERE id=?', (rid,)).fetchone())

    @app.post('/api/master/agents', status_code=201)
    def create_agent(payload: AgentCreate, user=Depends(supervisor)):
        # Hash outside the write lock. Never write plaintext credentials to audit.
        hashed = password_hash(payload.password)
        with db.connect(write=True) as conn:
            if conn.execute('SELECT 1 FROM agents WHERE upper(id)=upper(?)', (payload.id,)).fetchone():
                raise HTTPException(409, 'Kode petugas sudah ada.')
            if conn.execute('SELECT 1 FROM users WHERE lower(username)=lower(?)', (payload.username,)).fetchone():
                raise HTTPException(409, 'Username sudah digunakan.')
            if conn.execute('SELECT count(*) FROM agents').fetchone()[0] >= 200:
                raise HTTPException(409, 'Prototype dibatasi 200 petugas.')
            data = payload.model_dump(exclude={'id', 'username', 'password'})
            agent_rules(conn, data, clock())
            conn.execute(f'INSERT INTO agents(id,{",".join(data)}) VALUES ({",".join("?" for _ in range(len(data)+1))})', (payload.id, *data.values()))
            conn.execute('INSERT INTO users VALUES (?,?,?,?,?)', ('USR-'+uuid4().hex, payload.username, hashed, 'agent', payload.id))
            audit(conn, user, 'create_agent', None, dict(agent_id=payload.id, username=payload.username, **data), clock())
            return dict(conn.execute('SELECT * FROM agents WHERE id=?', (payload.id,)).fetchone())

    @app.patch('/api/master/agents/{aid}')
    def edit_agent(aid: str, payload: AgentEdit, user=Depends(supervisor)):
        with db.connect(write=True) as conn:
            row = conn.execute('SELECT * FROM agents WHERE id=?', (aid,)).fetchone()
            if not row: raise HTTPException(404, 'Petugas tidak ditemukan.')
            if row['version'] != payload.expected_version: raise HTTPException(409, 'Profil petugas berubah. Muat ulang master.')
            data = payload.model_dump(exclude={'expected_version', 'reason'})
            agent_rules(conn, data, clock(), row)
            conn.execute(f'UPDATE agents SET {",".join(k+"=?" for k in data)},version=version+1 WHERE id=?', (*data.values(), aid))
            audit(conn, user, 'update_agent_profile', None, dict(agent_id=aid, before=dict(row), after=data, reason=payload.reason), clock())
            return dict(conn.execute('SELECT * FROM agents WHERE id=?', (aid,)).fetchone())

    @app.get('/api/cases/{case_id}/assignment-options')
    def assignment_options(case_id: str, user=Depends(supervisor)):
        with db.connect() as conn:
            conn.execute('BEGIN')
            return override_options(conn, require_case(conn, case_id, user), clock())

    @app.post('/api/cases/{case_id}/override-assignment')
    def override(case_id: str, payload: OverrideInput, user=Depends(supervisor)):
        with db.connect(write=True) as conn:
            return perform_override(conn, case_id, payload, user, clock())
