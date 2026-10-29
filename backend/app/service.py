import json
from datetime import timedelta

from fastapi import HTTPException

from .domain import MODEL_VERSION, TERMINAL, day_bounds, instant, score_case, target_team, timestamp
from .scoring import assignment_preview
from .historical import encode
from .policy import success_deadline
from .operation_events import agent_account_active,assignment_event


def require_case(conn, case_id, user):
    row = conn.execute('SELECT * FROM cases WHERE id=?', (case_id,)).fetchone()
    if row is None or (user['role'] == 'agent' and row['agent_id'] != user['agent_id']):
        raise HTTPException(404, 'Kasus tidak ditemukan.')
    return dict(row)


def audit(conn, user, action, case_id, detail, now):
    conn.execute('INSERT INTO audit(actor_id,action,case_id,detail,created_at) VALUES (?,?,?,?,?)',
                 (user['id'], action, case_id, json.dumps(detail, ensure_ascii=False), timestamp(now)))


def agent_load(conn, agent_id, now):
    start, end = day_bounds(now)
    daily = conn.execute('SELECT COUNT(*) FROM assignments WHERE agent_id=? AND assigned_at>=? AND assigned_at<?',
                         (agent_id, start, end)).fetchone()[0]
    active = conn.execute('SELECT COUNT(*) FROM assignments WHERE agent_id=? AND ended_at IS NULL', (agent_id,)).fetchone()[0]
    return daily, active


def recommendations(conn, case, now):
    if not conn.execute('SELECT 1 FROM regions WHERE id=? AND active=1', (case['region_id'],)).fetchone():
        return []
    team = target_team(case)
    candidates = []
    for row in conn.execute('SELECT * FROM agents WHERE region_id=? AND kind=? AND team=? AND active=1 ORDER BY id',
                            (case['region_id'], case['kind'], team)):
        agent = dict(row)
        if not agent_account_active(conn,agent['id']):continue
        daily, active = agent_load(conn, agent['id'], now)
        remaining = max(0, min(agent['capacity'] - daily, agent['capacity'] - active))
        candidates.append(dict(agent_id=agent['id'], name=agent['name'], team=team, channel=agent['channel'],
                               daily_load=daily, active_load=active, capacity=agent['capacity'], remaining=remaining,
                               eligible=remaining > 0, reason=f"Wilayah cocok · tim {team} · sisa kapasitas {remaining}"))
    candidates.sort(key=lambda a: (-a['remaining'], a['agent_id']))
    return candidates


def assign_one(conn, case, user, now, reason='Auto-assignment berdasarkan aturan demo', agent_id=None):
    if case['status'] in TERMINAL or case['agent_id'] is not None:
        return dict(case_id=case['id'], assigned=False, reason='Kasus sudah ditugaskan atau sudah selesai.')
    case, prediction = assignment_preview(conn, case, now)
    choices = recommendations(conn, case, now)
    if agent_id is not None:
        choices = [a for a in choices if a['agent_id'] == agent_id]
    if not choices or not choices[0]['eligible']:
        return dict(case_id=case['id'], assigned=False, reason='Tidak ada petugas aktif dengan tim/wilayah/kapasitas yang sesuai.')
    candidate = choices[0]
    cycle = case['cycle'] + 1
    # Collection SLA is 72 hours, origination follow-up SLA is a documented demo assumption.
    due = now + timedelta(hours=prediction['policy']['followup_hours'])
    profile = conn.execute('SELECT * FROM agents WHERE id=?', (candidate['agent_id'],)).fetchone()
    conn.execute('INSERT INTO assignments(case_id,agent_id,cycle,assigned_at,due_at,score,reason,actor_id,agent_name,agent_team,agent_channel) VALUES (?,?,?,?,?,?,?,?,?,?,?)',
                 (case['id'], candidate['agent_id'], cycle, timestamp(now), timestamp(due), case['score'], reason, user['id'], profile['name'], profile['team'], profile['channel']))
    # Preserve origination progress (documents/qualification) across reassignment.
    status = case['status'] if case['status'] in {'documents', 'qualified'} else 'assigned'
    conn.execute('UPDATE cases SET agent_id=?,cycle=?,assigned_at=?,due_at=?,status=?,score=?,score_version=?,version=version+1 WHERE id=?',
                 (candidate['agent_id'], cycle, timestamp(now), timestamp(due), status, case['score'], case['score_version'], case['id']))
    conn.execute('INSERT INTO ml_predictions(case_id,cycle,payload) VALUES (?,?,?)',(case['id'],cycle,encode(prediction)))
    assignment_event(conn,case['id'],cycle,candidate['agent_id'],now)
    audit(conn, user, 'assign', case['id'], dict(agent_id=candidate['agent_id'], cycle=cycle, reason=reason), now)
    return dict(case_id=case['id'], assigned=True, agent_id=candidate['agent_id'], cycle=cycle, reason=candidate['reason'])


def reassign(conn, case, user, payload, now, agent_id=None):
    if case['version'] != payload.expected_version:
        raise HTTPException(409, 'Kasus berubah. Muat ulang sebelum penugasan ulang.')
    if case['status'] in TERMINAL or not case['agent_id']:
        raise HTTPException(409, 'Penugasan ulang hanya untuk kasus aktif yang sudah ditugaskan.')
    current = conn.execute('SELECT * FROM assignments WHERE case_id=? AND ended_at IS NULL', (case['id'],)).fetchone()
    deadline = success_deadline(current) if case['kind']=='collection' else instant(current['due_at'])
    outcome = 'no_success' if now > deadline else 'superseded'
    conn.execute('UPDATE assignments SET ended_at=?,outcome=? WHERE id=?', (timestamp(now), outcome, current['id']))
    codes = [r[0] for r in conn.execute('SELECT code FROM activities WHERE assignment_id=?', (current['id'],))]
    score, reasons = score_case(case, codes)
    conn.execute('UPDATE cases SET agent_id=NULL,assigned_at=NULL,due_at=NULL,score=?,score_version=?,version=version+1 WHERE id=?', (score, MODEL_VERSION, case['id']))
    fresh = dict(conn.execute('SELECT * FROM cases WHERE id=?', (case['id'],)).fetchone())
    result = assign_one(conn, fresh, user, now, payload.reason, agent_id=agent_id)
    if not result['assigned']:
        # Exception rolls back ending the old assignment too.
        raise HTTPException(409, result['reason'])
    audit(conn, user, 'reassign', case['id'], dict(reason=payload.reason, previous_outcome=outcome, score_reasons=reasons), now)
    return result


def add_activity(conn, case, user, payload, now):
    prior = conn.execute('SELECT * FROM activities WHERE request_key=?', (payload.request_key,)).fetchone()
    if prior:
        same = prior['case_id'] == case['id'] and prior['actor_id'] == user['id']
        same = same and all(prior[k] == getattr(payload, k) for k in ('code', 'note', 'amount', 'promise_date'))
        if not same:
            raise HTTPException(409, 'Kunci permintaan sudah digunakan untuk aktivitas berbeda.')
        return dict(activity=dict(prior), replayed=True)
    if case['version'] != payload.expected_version:
        raise HTTPException(409, 'Kasus berubah. Muat ulang sebelum menyimpan aktivitas.')
    if not case['agent_id'] or case['status'] in TERMINAL:
        raise HTTPException(409, 'Aktivitas hanya bisa dicatat pada kasus aktif yang sudah ditugaskan.')
    collection = {'contacted', 'unreachable', 'promise', 'payment'}
    origination = {'contacted', 'unreachable', 'documents', 'qualified', 'disburse', 'reject'}
    if payload.code not in (collection if case['kind'] == 'collection' else origination):
        raise HTTPException(422, 'Jenis aktivitas tidak cocok dengan alur kasus.')
    if payload.code in {'payment', 'disburse'}:
        if payload.amount <= 0:
            raise HTTPException(422, 'Nominal pembayaran/pencairan harus positif.')
    elif payload.amount:
        raise HTTPException(422, 'Nominal hanya untuk pembayaran atau pencairan.')
    if payload.code != 'promise' and payload.promise_date:
        raise HTTPException(422, 'Tanggal janji hanya untuk aktivitas janji bayar.')
    if payload.code == 'promise':
        try:
            promise = instant(payload.promise_date or '')
            if promise.tzinfo is None or promise < now:
                raise ValueError()
        except (ValueError, TypeError):
            raise HTTPException(422, 'Tanggal janji harus bertimezone dan tidak boleh di masa lalu.')
    current = conn.execute('SELECT * FROM assignments WHERE case_id=? AND ended_at IS NULL', (case['id'],)).fetchone()
    status, paid, documents = case['status'], case['paid'], case['documents_complete']
    if payload.code == 'payment':
        if paid + payload.amount > case['amount']:
            raise HTTPException(422, 'Pembayaran melebihi sisa tagihan.')
        paid += payload.amount
        status = 'paid' if paid == case['amount'] else 'in_progress'
    elif payload.code == 'documents':
        if status == 'qualified':
            raise HTTPException(409, 'Pengajuan sudah lolos verifikasi dokumen.')
        documents, status = 1, 'documents'
    elif payload.code == 'qualified':
        if not documents:
            raise HTTPException(409, 'Lengkapi dokumen sebelum verifikasi pengajuan.')
        status = 'qualified'
    elif payload.code == 'disburse':
        if status != 'qualified':
            raise HTTPException(409, 'Pengajuan harus lolos verifikasi sebelum pencairan simulasi.')
        if payload.amount != case['amount']:
            raise HTTPException(422, 'Nominal pencairan demo harus sama dengan nominal pengajuan.')
        paid, status = payload.amount, 'disbursed'
    elif payload.code == 'reject':
        if len(payload.note) < 5:
            raise HTTPException(422, 'Alasan penolakan wajib diisi (minimal 5 karakter).')
        status = 'rejected'
    elif payload.code == 'promise':
        status = 'promised'
    elif status == 'assigned':
        status = 'in_progress'
    cursor = conn.execute('INSERT INTO activities(case_id,assignment_id,actor_id,code,note,amount,promise_date,created_at,request_key) VALUES (?,?,?,?,?,?,?,?,?)',
                          (case['id'], current['id'], user['id'], payload.code, payload.note, payload.amount,
                           payload.promise_date, timestamp(now), payload.request_key))
    conn.execute('UPDATE cases SET status=?,paid=?,documents_complete=?,version=version+1 WHERE id=?', (status, paid, documents, case['id']))
    if status in TERMINAL:
        success = status == 'disbursed' or (status == 'paid' and now <= success_deadline(current))
        conn.execute('UPDATE assignments SET ended_at=?,outcome=? WHERE id=?',
                     (timestamp(now), 'success' if success else 'no_success', current['id']))
    audit(conn, user, 'activity', case['id'], dict(code=payload.code, amount=payload.amount, resulting_status=status), now)
    activity = dict(conn.execute('SELECT * FROM activities WHERE id=?', (cursor.lastrowid,)).fetchone())
    return dict(activity=activity, replayed=False)
