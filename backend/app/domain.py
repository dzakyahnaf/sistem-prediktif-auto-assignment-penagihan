from datetime import datetime, timedelta, timezone

TERMINAL = {'paid', 'disbursed', 'rejected'}
MODEL_VERSION = 'rules-demo-v1'
JAKARTA = timezone(timedelta(hours=7))


def timestamp(value: datetime) -> str:
    return value.astimezone(timezone.utc).isoformat(timespec='seconds')


def instant(value: str) -> datetime:
    return datetime.fromisoformat(value)


def day_bounds(now: datetime) -> tuple[str, str]:
    start = now.astimezone(JAKARTA).replace(hour=0, minute=0, second=0, microsecond=0)
    return timestamp(start), timestamp(start + timedelta(days=1))


def score_case(case, previous_codes=(), policy=None) -> tuple[float, list[str]]:
    """An explainable priority index, deliberately NOT a probability or trained ML."""
    policy = policy or {}
    if case['kind'] == 'collection':
        base = policy.get('collection_base',84) - min(case['dpd'], 120) * policy.get('dpd_penalty',.43)
        base -= {'Low': 0, 'Medium': 10, 'High': 23}[case['difficulty']]
        reasons = [f"Keterlambatan {case['dpd']} hari", f"Kesulitan {case['difficulty']}"]
    else:
        base = 25 + case['interest'] * policy.get('interest_weight',11) + int(case['documents_complete']) * policy.get('document_bonus',18)
        base += min(case['income'] / max(case['amount'], 1), 1) * policy.get('income_bonus',12)
        reasons = [f"Minat {case['interest']}/5", 'Dokumen lengkap' if case['documents_complete'] else 'Dokumen belum lengkap']
    if 'unreachable' in previous_codes:
        base -= 12
        reasons.append('Riwayat siklus selesai: tidak terhubung')
    if 'promise' in previous_codes:
        base += 5
        reasons.append('Riwayat siklus selesai: janji bayar')
    return round(max(5, min(95, base)), 1), reasons


def target_team(case) -> str:
    # Explicit prototype assumption: A=Tele, B=Lapangan. Medium threshold=60.
    if case['difficulty'] == 'Low':
        return 'A'
    if case['difficulty'] == 'High':
        return 'B'
    return 'A' if case['score'] >= case.get('medium_threshold',60) else 'B'
