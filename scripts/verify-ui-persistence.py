"""Verify UI-created demo records across real API process restarts on a DB copy.

The live database is only read through SQLite's backup API. No demo data is reset.
Run with the project's .venv interpreter after completing browser workflows.
"""
import json
import os
from contextlib import closing
from pathlib import Path
import socket
import sqlite3
import subprocess
import sys
import tempfile
import time
from urllib.error import URLError
from urllib.request import Request, urlopen


ROOT = Path(__file__).resolve().parents[1]


def request(base, path, token=None, payload=None):
    headers = {'Content-Type': 'application/json'}
    if token:
        headers['Authorization'] = f'Bearer {token}'
    data = json.dumps(payload).encode() if payload is not None else None
    with urlopen(Request(base + path, data=data, headers=headers), timeout=3) as response:
        return json.load(response)


def snapshot(db_path, case_ids):
    with socket.socket() as listener:
        listener.bind(('127.0.0.1', 0))
        port = listener.getsockname()[1]
    base = f'http://127.0.0.1:{port}'
    env = {**os.environ, 'DATABASE_PATH': str(db_path)}
    process = subprocess.Popen(
        [sys.executable, '-m', 'uvicorn', 'app.main:app', '--host', '127.0.0.1',
         '--port', str(port), '--log-level', 'error'],
        cwd=ROOT / 'backend', env=env, stdout=subprocess.DEVNULL,
    )
    try:
        for _ in range(100):
            if process.poll() is not None:
                raise RuntimeError('Backend stopped before becoming ready.')
            try:
                request(base, '/api/health')
                break
            except (URLError, TimeoutError):
                time.sleep(.1)
        else:
            raise RuntimeError('Backend did not become ready.')
        session = request(base, '/api/auth/login', payload={
            'username': 'supervisor', 'password': 'DemoAssignment!2026',
        })
        token = session['access_token']
        details = {cid: request(base, f'/api/cases/{cid}', token) for cid in case_ids}
        dashboard = request(base, '/api/dashboard', token)['streams']
        return {'details': details, 'dashboard': dashboard}
    finally:
        process.terminate()
        process.wait(timeout=10)


def main():
    source = ROOT / 'runtime' / 'assignment.db'
    with tempfile.TemporaryDirectory(prefix='assignment-ui-restart-') as folder:
        copy = Path(folder) / 'assignment.db'
        with closing(sqlite3.connect(source.as_uri() + '?mode=ro', uri=True)) as live:
            case_ids = [row[0] for row in live.execute(
                "SELECT id FROM cases WHERE customer LIKE 'UAT S2 %' ORDER BY id")]
            if not case_ids:
                raise RuntimeError('No browser UAT S2 records found; complete the UI scenarios first.')
            with closing(sqlite3.connect(copy)) as target:
                live.backup(target)
        before = snapshot(copy, case_ids)
        after = snapshot(copy, case_ids)
        if before != after:
            raise AssertionError('Case details or dashboard changed across process restart.')
        print(json.dumps({
            'result': 'PASS', 'database': 'temporary SQLite backup of runtime/assignment.db',
            'process_starts': 2, 'live_database_modified': False,
            'cases': [{
                'id': cid, 'status': data['case']['status'], 'paid': data['case']['paid'],
                'cycle': data['case']['cycle'], 'activities': len(data['activities']),
                'assignments': len(data['assignments']),
            } for cid, data in after['details'].items()],
            'dashboard': after['dashboard'],
        }, indent=2))


if __name__ == '__main__':
    main()
