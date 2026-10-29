"""Operational snapshots. A date range selects cohorts, not transaction dates."""
import csv
import io
from dataclasses import dataclass
from datetime import date, datetime, time, timedelta
from typing import Literal

from fastapi import HTTPException, Query

from .domain import JAKARTA, TERMINAL, timestamp
from .schemas import Kind
from .master import agent_scopes


@dataclass(frozen=True)
class ReportFilter:
    kind: str
    view: str = 'cases'
    region_id: str | None = None
    agent_id: str | None = None
    status: str | None = None
    date_from: date | None = None
    date_to: date | None = None
    q: str | None = None


def report_filters(kind: Kind, view: Literal['cases', 'cycles'] = 'cases',
                   region_id: str | None = Query(None, max_length=20),
                   agent_id: str | None = Query(None, max_length=40),
                   status: str | None = Query(None, max_length=30),
                   date_from: date | None = None, date_to: date | None = None,
                   q: str | None = Query(None, max_length=100)):
    if date_from and date_to and date_from > date_to:
        raise HTTPException(422, 'Tanggal awal tidak boleh melewati tanggal akhir.')
    # Adding a day for the exclusive end must remain representable.
    if date_from == date.min or date_to == date.max:
        raise HTTPException(422, 'Tanggal akhir di luar rentang yang didukung.')
    states = {'new', 'assigned', 'in_progress'} | ({'promised', 'paid'} if kind == 'collection' else {'documents', 'qualified', 'disbursed', 'rejected'})
    if status and status not in (states if view == 'cases' else {'active', 'overdue', 'success', 'no_success', 'superseded'}):
        raise HTTPException(422, 'Status/hasil tidak sesuai jenis laporan.')
    if view == 'cycles' and agent_id == 'unassigned':
        raise HTTPException(422, 'Siklus selalu memiliki petugas.')
    return ReportFilter(kind, view, region_id, agent_id, status, date_from, date_to, q.strip() if q else None)


def report_rows(conn, filters: ReportFilter, now: datetime):
    f = filters
    if f.region_id and not conn.execute('SELECT 1 FROM regions WHERE id=?', (f.region_id,)).fetchone():
        raise HTTPException(422, 'Wilayah laporan tidak dikenal.')
    if f.agent_id and f.agent_id != 'unassigned':
        agent = conn.execute('SELECT * FROM agents WHERE id=?', (f.agent_id,)).fetchone()
        if not agent or not any(s['kind'] == f.kind and (not f.region_id or s['region_id'] == f.region_id) for s in agent_scopes(conn, agent)):
            raise HTTPException(422, 'Petugas tidak sesuai alur/wilayah laporan.')
    terms, args = ['c.kind=?'], [f.kind]
    agent_column = 'c.agent_id' if f.view == 'cases' else 'a.agent_id'
    date_column = 'c.created_at' if f.view == 'cases' else 'a.assigned_at'
    if f.region_id:
        terms.append('c.region_id=?'); args.append(f.region_id)
    if f.agent_id == 'unassigned':
        terms.append('c.agent_id IS NULL')
    elif f.agent_id:
        terms.append(f'{agent_column}=?'); args.append(f.agent_id)
    if f.date_from:
        terms.append(f'{date_column}>=?')
        args.append(timestamp(datetime.combine(f.date_from, time.min, JAKARTA)))
    if f.date_to:
        terms.append(f'{date_column}<?')
        args.append(timestamp(datetime.combine(f.date_to + timedelta(days=1), time.min, JAKARTA)))
    if f.q:
        literal = f.q.replace('\\', '\\\\').replace('%', '\\%').replace('_', '\\_')
        terms.append("(c.customer LIKE ? ESCAPE '\\' OR c.id LIKE ? ESCAPE '\\')")
        args.extend([f'%{literal}%'] * 2)
    if f.status:
        if f.view == 'cases':
            terms.append('c.status=?'); args.append(f.status)
        elif f.status in {'active', 'overdue'}:
            terms.append('a.ended_at IS NULL')
            if f.status == 'overdue':
                terms.append('a.due_at<?'); args.append(timestamp(now))
        else:
            terms.append('a.outcome=?'); args.append(f.status)
    where = ' WHERE ' + ' AND '.join(terms)
    if f.view == 'cases':
        sql = '''SELECT c.id,c.kind,c.customer,c.region_id,r.name region_name,c.difficulty,
                 c.amount,c.paid,c.amount-c.paid outstanding,c.status,c.score,c.score_version,
                 c.agent_id,g.name agent_name,c.cycle,c.created_at,c.assigned_at,c.due_at,c.source
                 FROM cases c JOIN regions r ON r.id=c.region_id LEFT JOIN agents g ON g.id=c.agent_id'''
        rows = [dict(r) for r in conn.execute(sql + where + ' ORDER BY c.created_at DESC,c.id', args)]
    else:
        # Aggregate once per assignment before joining; never sum case.paid across cycles.
        sql = '''SELECT a.id assignment_id,c.id case_id,c.kind,c.customer,c.region_id,r.name region_name,
                 a.agent_id,COALESCE(a.agent_name,g.name) agent_name,COALESCE(a.agent_team,g.team) team,a.cycle,a.assigned_at,a.due_at,a.ended_at,
                 COALESCE(a.outcome,'active') outcome,a.score,c.status case_status,
                 COALESCE(v.realized,0) realized,COALESCE(v.activity_count,0) activity_count
                 FROM assignments a JOIN cases c ON c.id=a.case_id JOIN agents g ON g.id=a.agent_id
                 JOIN regions r ON r.id=c.region_id LEFT JOIN (
                   SELECT assignment_id,COUNT(*) activity_count,
                   SUM(CASE WHEN code IN ('payment','disburse') THEN amount ELSE 0 END) realized
                   FROM activities GROUP BY assignment_id
                 ) v ON v.assignment_id=a.id'''
        rows = [dict(r) for r in conn.execute(sql + where + ' ORDER BY a.assigned_at DESC,a.id DESC', args)]
        for row in rows:
            row['overdue'] = row['ended_at'] is None and row['due_at'] < timestamp(now)
    return rows


def summarize(rows, view):
    total = len(rows)
    if view == 'cases':
        return dict(total=total, amount=sum(r['amount'] for r in rows), realized=sum(r['paid'] for r in rows),
                    outstanding=sum(r['outstanding'] for r in rows),
                    unassigned=sum(r['agent_id'] is None and r['status'] not in TERMINAL for r in rows),
                    active=sum(r['agent_id'] is not None and r['status'] not in TERMINAL for r in rows),
                    completed=sum(r['status'] in {'paid', 'disbursed'} for r in rows),
                    rejected=sum(r['status'] == 'rejected' for r in rows))
    counts = {key: sum(r['outcome'] == key for r in rows) for key in ['active', 'success', 'no_success', 'superseded']}
    evaluated = counts['success'] + counts['no_success']
    return dict(total=total, **counts, overdue=sum(r['overdue'] for r in rows),
                realized=sum(r['realized'] for r in rows), activity_count=sum(r['activity_count'] for r in rows),
                evaluated=evaluated, success_rate=round(100 * counts['success'] / evaluated, 1) if evaluated else None)


def report_result(rows, filters, now, offset, limit):
    groups = {}
    for row in rows:
        groups.setdefault(row['agent_id'], []).append(row)
    by_agent = [dict(agent_id=aid, agent_name=group[0]['agent_name'] or 'Belum ditugaskan',
                     **summarize(group, filters.view)) for aid, group in groups.items()]
    by_agent.sort(key=lambda g: (-g['total'], g['agent_id'] or ''))
    return dict(view=filters.view, kind=filters.kind, generated_at=timestamp(now), timezone='Asia/Jakarta',
                date_basis='created_at' if filters.view == 'cases' else 'assigned_at',
                filters={k: v.isoformat() if isinstance(v, date) else v for k, v in vars(filters).items()},
                summary=summarize(rows, filters.view), by_agent=by_agent,
                items=rows[offset:offset + limit], total=len(rows), offset=offset, limit=limit)


CASE_COLUMNS = ['id', 'kind', 'customer', 'region_id', 'difficulty', 'amount', 'paid', 'status', 'score',
                'score_version', 'agent_id', 'cycle', 'source', 'region_name', 'agent_name', 'outstanding',
                'created_at', 'assigned_at', 'due_at']
CYCLE_COLUMNS = ['assignment_id', 'case_id', 'kind', 'customer', 'region_id', 'region_name', 'agent_id',
                 'agent_name', 'team', 'cycle', 'assigned_at', 'due_at', 'ended_at', 'outcome', 'score',
                 'case_status', 'realized', 'activity_count', 'overdue']


def csv_content(rows, filters, now):
    stream = io.StringIO(newline='')
    writer = csv.writer(stream)
    columns = CASE_COLUMNS if filters.view == 'cases' else CYCLE_COLUMNS
    metadata = dict(generated_at=timestamp(now), date_basis='created_at' if filters.view == 'cases' else 'assigned_at',
                    date_from_wib=filters.date_from or '', date_to_wib=filters.date_to or '')
    writer.writerow(columns + list(metadata))
    for row in rows:
        values = [row[key] for key in columns] + list(metadata.values())
        # Leading whitespace/control characters must not hide spreadsheet formulas.
        writer.writerow(["'" + v if isinstance(v, str) and (v[:1] in ('\t', '\r', '\n') or v.lstrip()[:1] in ('=', '+', '-', '@')) else v for v in values])
    return '\ufeff' + stream.getvalue()
