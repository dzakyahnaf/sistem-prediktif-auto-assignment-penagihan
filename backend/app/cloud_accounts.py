"""Cloud-only provisioning: private owner/agents plus a public read-only viewer."""
import secrets
from .security import password_hash,verify_password
from .domain import timestamp
from .seed import DEMO_PASSWORD

def provision(db,admin_password,now):
    with db.connect(write=True) as c:
        owner=c.execute("SELECT * FROM users WHERE id='USR-SUP' AND username='supervisor' AND role='supervisor'").fetchone()
        if not owner:raise ValueError('Expected supervisor account was not found; no accounts overwritten.')
        if not verify_password(admin_password,owner['password_hash']):
            c.execute('UPDATE users SET password_hash=? WHERE id=?',(password_hash(admin_password),owner['id']))
            c.execute('DELETE FROM sessions WHERE user_id=?',(owner['id'],))
            c.execute('INSERT INTO audit(actor_id,action,detail,created_at) VALUES (?,?,?,?)',(owner['id'],'cloud_owner_secret_rotated','{}',timestamp(now)))
        for row in c.execute("SELECT * FROM users WHERE role='agent'").fetchall():
            if verify_password(DEMO_PASSWORD,row['password_hash']):
                c.execute('UPDATE users SET password_hash=? WHERE id=?',(password_hash(secrets.token_urlsafe(32)),row['id']))
                c.execute('DELETE FROM sessions WHERE user_id=?',(row['id'],))
        visitor=c.execute("SELECT * FROM users WHERE username='demo' OR id='USR-PUBLIC'").fetchall()
        if visitor:
            if len(visitor)!=1 or visitor[0]['id']!='USR-PUBLIC' or visitor[0]['username']!='demo' or visitor[0]['role']!='viewer':
                raise ValueError('Public viewer identity is already used; no account overwritten.')
        else:c.execute('INSERT INTO users VALUES (?,?,?,?,?)',('USR-PUBLIC','demo',password_hash(DEMO_PASSWORD),'viewer',None))
