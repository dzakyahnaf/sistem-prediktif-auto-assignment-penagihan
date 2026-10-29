"""Operational policy: revisions affect future decisions, never closed snapshots."""
import json
from datetime import timedelta
from pydantic import Field,field_validator
from .schemas import Input
from .domain import instant,timestamp

class PolicyConfig(Input):
    medium_threshold: float = Field(default=60, ge=1, le=99, allow_inf_nan=False)
    collection_followup_hours: int = Field(default=72, ge=1, le=168, strict=True)
    origination_followup_hours: int = Field(default=72, ge=1, le=168, strict=True)
    collection_base: float = Field(default=84, ge=50, le=95, allow_inf_nan=False)
    dpd_penalty: float = Field(default=.43, ge=0, le=1, allow_inf_nan=False)
    interest_weight: float = Field(default=11, ge=0, le=15, allow_inf_nan=False)
    document_bonus: float = Field(default=18, ge=0, le=25, allow_inf_nan=False)
    income_bonus: float = Field(default=12, ge=0, le=20, allow_inf_nan=False)
    segment_release_id: str | None = Field(default=None,min_length=5,max_length=64)

    @field_validator('*',mode='before')
    @classmethod
    def numeric_types(cls,value):
        if isinstance(value,bool):raise ValueError('Angka kebijakan tidak boleh boolean.')
        return value

def current_policy(conn):
    row = conn.execute('SELECT * FROM policy_revisions ORDER BY revision DESC LIMIT 1').fetchone()
    return dict(revision=row['revision'] if row else 0,config=json.loads(row['config']) if row else PolicyConfig().model_dump())

def rule_version(revision):
    return 'rules-demo-v1' if revision==0 else f'rules-policy-v{revision}'

def success_deadline(assignment):
    # Collection success stays 72h, independently of configurable follow-up SLA.
    return instant(assignment['assigned_at'])+timedelta(hours=72)

def snapshot_policy(conn,kind,now):
    p=current_policy(conn)
    return dict(**p,collection_success_hours=72,followup_hours=p['config'][kind+'_followup_hours'],
        outcome_due_at=timestamp(now+timedelta(hours=72)) if kind=='collection' else None)
