from datetime import datetime, timezone
from random import Random

from .domain import MODEL_VERSION, score_case, timestamp
from .security import password_hash
from .scoring import capture_origin

DEMO_PASSWORD = 'DemoAssignment!2026'


def seed_demo(db, now: datetime | None = None):
    """Idempotent, deterministic feature generation; never imports real customer data."""
    now = now or datetime.now(timezone.utc)
    rng = Random(271026)
    with db.connect(write=True) as conn:
        if conn.execute('SELECT COUNT(*) FROM users').fetchone()[0]:
            return
        regions = [('SMG', 'Semarang'), ('SBY', 'Surabaya'), ('BDG', 'Bandung')]
        conn.executemany('INSERT INTO regions(id,name) VALUES (?,?)', regions)
        conn.execute('INSERT INTO users VALUES (?,?,?,?,?)',
                     ('USR-SUP', 'supervisor', password_hash(DEMO_PASSWORD), 'supervisor', None))
        for region, name in regions:
            for kind in ('collection', 'origination'):
                for team, channel in [('A', 'Tele'), ('B', 'Lapangan')]:
                    aid = f'{region}-{kind[:3]}-{team}'
                    conn.execute('INSERT INTO agents(id,name,region_id,kind,team,channel,approach,capacity,active) VALUES (?,?,?,?,?,?,?,?,?)',
                                 (aid, f'{channel} {name} {kind[:3].upper()}', region, kind,
                                  team, channel, 'Negosiasi' if team == 'A' else 'Pendampingan', 12, 1))
                    conn.execute('INSERT INTO users VALUES (?,?,?,?,?)',
                                 (f'USR-{aid}', aid.lower(), password_hash(DEMO_PASSWORD), 'agent', aid))
        for kind, prefix in [('collection', 'TAG'), ('origination', 'AJU')]:
            for i in range(1, 73):
                case = dict(id=f'{prefix}-{i:04}', kind=kind, customer=f'{"Debitur" if kind == "collection" else "Pemohon"} Demo {i:03}',
                            region_id=regions[(i-1) % 3][0], difficulty=['Low', 'Medium', 'High'][(i//3) % 3],
                            amount=rng.randrange(1, 15)*500_000 if kind == 'collection' else rng.randrange(5, 60)*1_000_000,
                            dpd=rng.choice([7, 14, 21, 30, 45, 60, 90]) if kind == 'collection' else 0,
                            income=rng.randrange(3, 16)*1_000_000 if kind == 'origination' else 0,
                            interest=rng.randint(1, 5) if kind == 'origination' else 0,
                            documents_complete=int(i % 3 == 0) if kind == 'origination' else 0,
                            created_at=timestamp(now), score_version=MODEL_VERSION)
                case['score'] = score_case(case)[0]
                columns = ','.join(case)
                conn.execute(f'INSERT INTO cases ({columns}) VALUES ({",".join("?" for _ in case)})', tuple(case.values()))
                capture_origin(conn,case)
