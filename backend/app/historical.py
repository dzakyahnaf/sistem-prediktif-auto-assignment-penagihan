"""Deterministic synthetic longitudinal history and point-in-time dataset builder.

No operational records, real identities, model probabilities or current-cycle
outcomes are used as predictors. Actions/propensities are observational metadata.
"""
from collections import Counter, defaultdict
from datetime import date, datetime, timedelta, timezone
import hashlib
import json
import math
import random

from pydantic import Field, model_validator
from .schemas import Input
from .domain import timestamp, instant

VERSION = 'history-simulator-v1'
FEATURE_VERSION = 'point-in-time-v1'
COMMON = ['region_id', 'difficulty', 'amount', 'age_days', 'decision_month', 'decision_weekday']
INITIAL = {
    'collection': COMMON + ['dpd'],
    'origination': COMMON + ['income', 'interest', 'documents_complete'],
}
PREVIOUS = ['closed_cycles', 'previous_contacts', 'previous_unreachable', 'previous_promises',
            'paid_before_decision', 'remaining_at_decision']
FEATURES = {kind: {'initial': fields, 'reassignment': fields + PREVIOUS +
            (['previous_documents', 'previous_qualified'] if kind == 'origination' else [])}
            for kind, fields in INITIAL.items()}
REASONS = {
    'censored': 'Jendela outcome belum selesai pada tanggal observasi.',
    'early_reassignment': 'Siklus dialihkan sebelum jendela outcome selesai.',
    'label_cross_boundary': 'Jendela label melewati batas partisi waktu.',
    'entity_cross_split': 'Identitas muncul di lebih dari satu partisi; seluruh sampelnya dikeluarkan.',
}


class HistoryConfig(Input):
    cases_per_kind: int = Field(default=3000, ge=100, le=5000, strict=True)
    seed: int = Field(default=281026, ge=1, le=2_000_000_000, strict=True)
    start_date: date = date(2024, 10, 1)
    train_until: date = date(2026, 2, 1)
    validation_until: date = date(2026, 6, 1)
    as_of: date = date(2026, 10, 1)
    origination_window_days: int = Field(default=30, ge=7, le=90, strict=True)

    @model_validator(mode='after')
    def dates(self):
        bounds = [self.start_date, self.train_until, self.validation_until, self.as_of]
        if not all(a < b for a, b in zip(bounds, bounds[1:])):
            raise ValueError('Urutan tanggal harus awal < batas train < batas validation < observasi.')
        if not 180 <= (self.as_of - self.start_date).days <= 1826:
            raise ValueError('Rentang histori harus 180–1826 hari.')
        if any((b-a).days <= self.origination_window_days + 7 for a, b in zip(bounds, bounds[1:])):
            raise ValueError('Tiap partisi perlu lebih panjang dari jendela pengajuan + 7 hari.')
        return self


def encode(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=True, allow_nan=False)


def content_hash(bundle):
    return hashlib.sha256(encode(bundle).encode()).hexdigest()


def midnight(value):
    return datetime.combine(value, datetime.min.time(), timezone.utc)


def simulate(config):
    """Return observed raw history only, truncated at the explicit UTC as-of."""
    rng = random.Random(config.seed)
    begin, asof = midnight(config.start_date), midnight(config.as_of)
    cases, decisions, events = [], [], []
    for kind in ('collection', 'origination'):
        for i in range(config.cases_per_kind):
            if i % 2 == 0:
                first = begin + timedelta(seconds=rng.randrange(int((asof-begin).total_seconds())-7200))
            created = min(first + timedelta(days=rng.randint(14, 60)) if i % 2 else first, asof-timedelta(hours=2))
            cid = f'H-{kind[:3]}-{i:06d}'
            case = dict(id=cid, entity_id=f'E-{kind[:3]}-{i//2:06d}', kind=kind,
                region_id=rng.choice(['SMG', 'SBY', 'BDG']), difficulty=rng.choice(['Low', 'Medium', 'High']),
                amount=rng.randint(2, 120)*500000, dpd=rng.randint(0, 150) if kind == 'collection' else 0,
                income=rng.randint(3, 25)*1000000 if kind == 'origination' else 0,
                interest=rng.randint(1, 5) if kind == 'origination' else 0,
                documents_complete=int(kind == 'origination' and rng.random() < .3), created_at=timestamp(created))
            cases.append(case)
            when = created + timedelta(hours=1)
            paid, terminal = 0, False
            # Unobserved latent variation affects outcomes, never the feature schema/export.
            latent = rng.gauss(0, .7)
            for cycle in (1, 2):
                if when >= asof or terminal: break
                team = 'A' if case['difficulty'] == 'Low' else 'B' if case['difficulty'] == 'High' else rng.choice(['A', 'B'])
                did = f'{cid}-C{cycle}'
                d = dict(id=did, case_id=cid, cycle=cycle, assigned_at=timestamp(when), team=team,
                    agent_id=f'H-{case["region_id"]}-{kind[:3]}-{team}',
                    assignment_propensity=.5 if case['difficulty'] == 'Medium' else 1.0,
                    policy_version='synthetic-exploration-v1')
                current = []
                def event(hours, code, amount=0):
                    current.append(dict(id=f'{did}-E{len(current)+1}', decision_id=did,
                                        at=timestamp(when+timedelta(hours=hours)), code=code, amount=amount))
                contact = rng.random() < .72
                event(8, 'contacted' if contact else 'unreachable')
                linear = (.9 - case['dpd']/100 if kind == 'collection' else
                          -.8 + case['interest']*.35 + min(case['income']/case['amount'], 2)*.3)
                linear += {'Low': .25, 'Medium': 0, 'High': -.4}[case['difficulty']] + latent
                probability = 1/(1+math.exp(-linear))
                early = rng.random() < .18
                close_hours = (48 if early else 120) if kind == 'collection' else (7*24 if early else 45*24)
                terminal_code, terminal_hour = None, None
                if kind == 'collection':
                    if rng.random() < .4: event(12, 'promise')
                    partial = int((case['amount']-paid)*.3) if rng.random() < .5 else 0
                    if partial: event(24, 'payment', partial)
                    if rng.random() < probability:
                        terminal_hour = rng.choice([36, 60, 72, 96, 114])
                        terminal_code = 'payment'
                        if terminal_hour <= close_hours:
                            event(terminal_hour, 'payment', case['amount']-paid-partial)
                else:
                    event(24, 'documents')
                    event(48, 'qualified')
                    if rng.random() < probability:
                        terminal_hour, terminal_code = rng.randint(3, 40)*24, 'disburse'
                    elif rng.random() < .45:
                        terminal_hour, terminal_code = rng.randint(3, 35)*24, 'reject'
                    if terminal_hour is not None and terminal_hour <= close_hours:
                        event(terminal_hour, terminal_code, case['amount'] if terminal_code == 'disburse' else 0)
                terminal = terminal_hour is not None and terminal_hour <= close_hours
                if terminal: close_hours = terminal_hour
                closed = when + timedelta(hours=close_hours)
                observed = [e for e in current if instant(e['at']) <= min(closed, asof)]
                paid += sum(e['amount'] for e in observed if e['code'] == 'payment')
                d.update(closed_at=timestamp(closed) if closed <= asof else None,
                         outcome=(terminal_code if terminal else 'transferred') if closed <= asof else 'open')
                decisions.append(d); events.extend(observed)
                if terminal or rng.random() > .65: break
                when = closed + timedelta(minutes=1)
    return dict(cases=cases, decisions=decisions, events=events)


def snapshot_features(case, when, previous, prior_events, stage):
    """Shared v1 feature contract for historical training and operational serving."""
    available = max([case['created_at']] + [p['closed_at'] for p in previous] + [e['at'] for e in prior_events])
    f = {k: case[k] for k in ('region_id', 'difficulty', 'amount')}
    f.update(age_days=(when-instant(case['created_at'])).days, decision_month=when.month, decision_weekday=when.weekday())
    if case['kind'] == 'collection': f['dpd'] = case['dpd'] + f['age_days']
    else: f.update({k: case[k] for k in ('income', 'interest', 'documents_complete')})
    paid = sum(e['amount'] for e in prior_events if e['code'] == 'payment')
    if stage == 'reassignment':
        counts = Counter(e['code'] for e in prior_events)
        f.update(closed_cycles=len(previous), previous_contacts=counts['contacted'], previous_unreachable=counts['unreachable'],
            previous_promises=counts['promise'], paid_before_decision=paid, remaining_at_decision=case['amount']-paid)
        if case['kind'] == 'origination': f.update(previous_documents=counts['documents'], previous_qualified=counts['qualified'])
    return f, available


def build_samples(raw, config):
    """Derive predictors from the case-at-entry and strictly closed prior cycles."""
    cases = {c['id']: c for c in raw['cases']}
    history, activity = defaultdict(list), defaultdict(list)
    for d in raw['decisions']: history[d['case_id']].append(d)
    for e in raw['events']: activity[e['decision_id']].append(e)
    asof = midnight(config.as_of)
    samples = []
    for d in sorted(raw['decisions'], key=lambda x: x['id']):
        case = cases[d['case_id']]; when = instant(d['assigned_at'])
        previous = [p for p in history[case['id']] if p['cycle'] < d['cycle'] and p['closed_at'] and instant(p['closed_at']) < when]
        prior_events = [e for p in previous for e in activity[p['id']] if instant(e['at']) < when]
        stage = 'initial' if d['cycle'] == 1 else 'reassignment'
        f, available = snapshot_features(case, when, previous, prior_events, stage)
        paid = sum(e['amount'] for e in prior_events if e['code'] == 'payment')
        hours = 72 if case['kind'] == 'collection' else config.origination_window_days*24
        ready = when+timedelta(hours=hours)
        current = [e for e in activity[d['id']] if instant(e['at']) <= ready]
        positive = paid+sum(e['amount'] for e in current if e['code'] == 'payment') >= case['amount'] if case['kind'] == 'collection' else any(e['code'] == 'disburse' for e in current)
        reason = 'censored' if ready > asof else 'early_reassignment' if d['outcome'] == 'transferred' and d['closed_at'] and instant(d['closed_at']) < ready else None
        label = None if reason else int(positive)
        split = 'train' if when < midnight(config.train_until) else 'validation' if when < midnight(config.validation_until) else 'test'
        end = midnight(config.train_until if split == 'train' else config.validation_until if split == 'validation' else config.as_of)
        if not reason and ready > end: reason = 'label_cross_boundary'
        samples.append(dict(id=d['id'], case_id=case['id'], entity_id=case['entity_id'], kind=case['kind'], stage=stage,
            decision_at=d['assigned_at'], feature_max_at=available, label_ready_at=timestamp(ready),
            features=f, label=label, split=split if not reason else 'excluded', exclusion=reason,
            team=d['team'], assignment_propensity=d['assignment_propensity']))
    # Purge entire entities whose eligible decisions cross temporal partitions.
    partitions = defaultdict(set)
    for s in samples:
        if s['split'] != 'excluded': partitions[s['entity_id']].add(s['split'])
    for s in samples:
        if len(partitions[s['entity_id']]) > 1 and s['split'] != 'excluded':
            s.update(split='excluded', exclusion='entity_cross_split')
    return samples


def validate_bundle(raw, samples, config):
    """Fail closed on corruption/leakage; this is run before any persistence."""
    issues = []
    cases = {c['id']: c for c in raw['cases']}; decisions = {d['id']: d for d in raw['decisions']}
    if len(cases) != len(raw['cases']) or len(decisions) != len(raw['decisions']): issues.append('duplicate_id')
    if len({e['id'] for e in raw['events']}) != len(raw['events']): issues.append('duplicate_event')
    asof = midnight(config.as_of)
    for c in cases.values():
        if not midnight(config.start_date) <= instant(c['created_at']) <= asof or c['amount'] <= 0: issues.append('invalid_case')
    cycle_keys = set()
    for d in raw['decisions']:
        case = cases.get(d['case_id'])
        key = (d['case_id'], d['cycle'])
        if key in cycle_keys: issues.append('duplicate_cycle')
        cycle_keys.add(key)
        if not case or not instant(case['created_at']) <= instant(d['assigned_at']) <= asof:
            issues.append('invalid_decision'); continue
        if d['closed_at'] and not instant(d['assigned_at']) <= instant(d['closed_at']) <= asof: issues.append('invalid_close')
        if case['difficulty'] in ('Low', 'High') and d['team'] != ('A' if case['difficulty'] == 'Low' else 'B'): issues.append('team_constraint')
        if d['assignment_propensity'] != (.5 if case['difficulty'] == 'Medium' else 1): issues.append('invalid_propensity')
        if d['cycle'] > 1:
            previous = next((p for p in raw['decisions'] if p['case_id'] == d['case_id'] and p['cycle'] == d['cycle']-1), None)
            if not previous or not previous['closed_at'] or previous['closed_at'] >= d['assigned_at']: issues.append('overlapping_cycle')
    for e in raw['events']:
        d = decisions.get(e['decision_id'])
        if not d or not instant(d['assigned_at']) < instant(e['at']) <= asof or (d['closed_at'] and e['at'] > d['closed_at']): issues.append('invalid_event_time')
        if e['amount'] < 0: issues.append('negative_money')
    groups = defaultdict(set)
    for s in samples:
        if set(s['features']) != set(FEATURES[s['kind']][s['stage']]): issues.append('feature_contract')
        if s['feature_max_at'] > s['decision_at']: issues.append('future_feature')
        if s['split'] != 'excluded':
            groups[s['entity_id']].add(s['split'])
            lower, upper = {'train': (config.start_date, config.train_until), 'validation': (config.train_until, config.validation_until), 'test': (config.validation_until, config.as_of)}[s['split']]
            if not midnight(lower) <= instant(s['decision_at']) < midnight(upper) or instant(s['label_ready_at']) > midnight(upper) or s['label'] not in (0, 1): issues.append('invalid_partition')
    if any(len(g) > 1 for g in groups.values()): issues.append('identity_overlap')
    if {s['id'] for s in samples} != set(decisions): issues.append('missing_sample')
    if samples != build_samples(raw, config): issues.append('snapshot_derivation_mismatch')
    if issues: raise ValueError('Historical quality gate failed: ' + ', '.join(sorted(set(issues))))


def create_dataset(config):
    raw = simulate(config); samples = build_samples(raw, config)
    validate_bundle(raw, samples, config)
    bundle = dict(**raw, samples=samples)
    datasets = []
    for kind in FEATURES:
        for stage in ('initial', 'reassignment'):
            selected = [s for s in samples if s['kind'] == kind and s['stage'] == stage]
            splits = {name: dict(total=sum(s['split'] == name for s in selected),
                positive=sum(s['split'] == name and s['label'] == 1 for s in selected),
                negative=sum(s['split'] == name and s['label'] == 0 for s in selected)) for name in ('train', 'validation', 'test')}
            sufficient = all(v['positive'] >= 20 and v['negative'] >= 20 for v in splits.values())
            datasets.append(dict(kind=kind, stage=stage, total=len(selected), splits=splits,
                excluded=dict(Counter(s['exclusion'] for s in selected if s['exclusion'])),
                demo_training_ready=sufficient))
    manifest = dict(simulator_version=VERSION, feature_version=FEATURE_VERSION, source='synthetic-longitudinal',
        data_sha256=content_hash(bundle), counts={k:len(v) for k,v in bundle.items()}, datasets=datasets,
        quality=dict(passed=True, feature_time_violations=0, identity_overlap=0, temporal_overlap=0),
        labels=dict(collection_hours=72, origination_days=config.origination_window_days),
        warnings=['Seluruh data/hasil adalah simulasi; bukan bukti efektivitas pada nasabah nyata.',
            'Label pengajuan memakai jendela konversi asumsi; bukan SLA operasional 72 jam.',
            'Propensity adalah peluang tim dari simulator. Low/High deterministik; tidak mendukung klaim uplift kausal.',
            'Kesiapan demo membutuhkan ≥20 label tiap kelas pada setiap partisi; bukan kelayakan ML produksi.'])
    return bundle, manifest


def dictionary():
    return dict(feature_version=FEATURE_VERSION, features=FEATURES, exclusions=REASONS,
        metadata_not_predictors=['id', 'case_id', 'entity_id', 'team', 'assignment_propensity', 'label', 'split', 'exclusion', 'label_ready_at'],
        time='UTC, batas tanggal eksklusif; label 1 jika lunas/pencairan pada atau sebelum deadline.',
        isolation='Raw history, target dan metadata dipisahkan dari features. Riwayat fitur hanya dari siklus terdahulu yang sudah ditutup.',
        entity_policy='Dua kasus sintetis per identitas; seluruh sampel eligible identitas lintas split dipurge. Label lintas batas juga dikeluarkan.')
