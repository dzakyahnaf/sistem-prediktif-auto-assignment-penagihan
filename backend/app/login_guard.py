"""Persistent, fixed-window failed-login budgets; never trusts forwarded IPs."""
from hashlib import sha256
from datetime import timedelta
from .domain import timestamp

WINDOW = timedelta(minutes=15)

def buckets(peer, username):
    return [(sha256(('pair\0'+peer+'\0'+username).encode()).hexdigest(),5),
            (sha256(('peer\0'+peer).encode()).hexdigest(),30)]

def check(conn, peer, username, now):
    cutoff=timestamp(now-WINDOW)
    conn.execute('DELETE FROM login_failures WHERE started_at<=?',(cutoff,))
    rows=[]
    for key,limit in buckets(peer,username):
        row=conn.execute('SELECT * FROM login_failures WHERE bucket=?',(key,)).fetchone()
        rows.append((key,limit,row))
    blocked=[r for _,limit,r in rows if r and r['failures']>=limit]
    if blocked:
        from datetime import datetime
        return max(1,max(int((datetime.fromisoformat(r['started_at'])+WINDOW-now).total_seconds())+1 for r in blocked)),rows
    return 0,rows

def failure(conn, rows, now):
    for key,_,row in rows:
        if row:conn.execute('UPDATE login_failures SET failures=failures+1 WHERE bucket=?',(key,))
        else:conn.execute('INSERT INTO login_failures VALUES (?,?,?)',(key,1,timestamp(now)))

def success(conn, peer, username):
    conn.execute('DELETE FROM login_failures WHERE bucket=?',(buckets(peer,username)[0][0],))
