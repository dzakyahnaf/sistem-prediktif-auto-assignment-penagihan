"""Add one aged synthetic assignment only to the existing Sprint12 UAT schema."""
from datetime import datetime,timedelta,timezone
import json,re,sys
from pathlib import Path
from fastapi.testclient import TestClient
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'backend'))
from app.main import create_app

def main():
    output=ROOT/'runtime/sprint12-sla-fixture.json'
    if output.exists():raise ValueError('Existing fixture preserved.')
    cfg=json.loads((ROOT/'runtime/sprint12-uat-config.json').read_text())
    if not re.fullmatch(r'uat_s12_[0-9a-f]{12}',cfg['schema']):raise ValueError('Only Sprint12 UAT is allowed.')
    when=datetime.now(timezone.utc)-timedelta(hours=100)
    with TestClient(create_app(cfg['url'],lambda:when,seed=False)) as client:
        r=client.post('/api/auth/login',json=dict(username='supervisor',password='DemoAssignment!2026'));r.raise_for_status()
        h={'Authorization':'Bearer '+r.json()['access_token']}
        r=client.post('/api/cases',headers=h,json=dict(kind='origination',customer='UAT S12 Fixture SLA',region_id='SMG',difficulty='Low',amount=2000000,income=5000000,interest=3));r.raise_for_status();cid=r.json()['id']
        r=client.post('/api/assignments',headers=h,json=dict(case_ids=[cid]));r.raise_for_status();assert r.json()['results'][0]['assigned']
        r=client.post('/api/auth/logout',headers=h);r.raise_for_status()
    output.write_text(json.dumps(dict(case_id=cid,assigned_at=when.isoformat(),setup='API fixture with synthetic clock, not browser creation'),indent=2),encoding='utf-8')
    print(json.dumps(dict(case_id=cid,setup='isolated UAT, aged 100h')))

if __name__=='__main__':main()
