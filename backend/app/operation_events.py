"""Transactional local events; no external messaging or personal destinations."""
from uuid import uuid4
from .domain import timestamp

def notify(conn,user_id,event_key,case_id,title,body,now):
    if not conn.execute('SELECT 1 FROM notifications WHERE event_key=?',(event_key,)).fetchone():
        conn.execute('INSERT INTO notifications(id,event_key,user_id,case_id,title,body,created_at,read_at) VALUES (?,?,?,?,?,?,?,?)',
            ('NTF-'+uuid4().hex[:16].upper(),event_key,user_id,case_id,title,body,timestamp(now),None))

def assignment_event(conn,case_id,cycle,agent_id,now):
    for row in conn.execute('SELECT id FROM users WHERE agent_id=?',(agent_id,)):
        notify(conn,row['id'],f'assignment:{case_id}:{cycle}:{row["id"]}',case_id,'Assignment baru',
            f'Anda menerima penugasan siklus{cycle}. Buka kasus untuk detail dalam scope Anda.',now)

def account_active(conn,user_id):
    row=conn.execute('SELECT active FROM user_controls WHERE user_id=?',(user_id,)).fetchone()
    return row is None or bool(row['active'])

def agent_account_active(conn,agent_id):
    return any(account_active(conn,r['id']) for r in conn.execute('SELECT id FROM users WHERE agent_id=?',(agent_id,)))
