from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, model_validator

Kind = Literal['collection', 'origination']


class Input(BaseModel):
    model_config = ConfigDict(extra='forbid', str_strip_whitespace=True)


class Login(Input):
    username: str = Field(min_length=1, max_length=80)
    password: str = Field(min_length=1, max_length=128)


class CaseCreate(Input):
    kind: Kind
    customer: str = Field(min_length=2, max_length=100)
    region_id: str = Field(min_length=1, max_length=20)
    difficulty: Literal['Low', 'Medium', 'High'] = 'Medium'
    amount: int = Field(gt=0, le=1_000_000_000, strict=True)
    dpd: int = Field(default=0, ge=0, le=3650, strict=True)
    income: int = Field(default=0, ge=0, le=1_000_000_000, strict=True)
    interest: int = Field(default=0, ge=0, le=5, strict=True)
    documents_complete: bool = False

    @model_validator(mode='after')
    def domain_fields(self):
        if self.kind == 'origination' and (self.income <= 0 or self.interest < 1 or self.dpd):
            raise ValueError('Pengajuan memerlukan penghasilan > 0, minat 1–5, dan DPD 0.')
        if self.kind == 'collection' and (self.income or self.interest or self.documents_complete):
            raise ValueError('Field penghasilan, minat, dan dokumen hanya untuk pengajuan.')
        return self


class AssignRequest(Input):
    case_ids: list[str] = Field(min_length=1, max_length=100)

    @model_validator(mode='after')
    def unique_ids(self):
        if len(self.case_ids) != len(set(self.case_ids)):
            raise ValueError('ID kasus tidak boleh berulang.')
        return self


class ReassignRequest(Input):
    expected_version: int = Field(ge=1)
    reason: str = Field(min_length=10, max_length=500)


class ActivityInput(Input):
    expected_version: int = Field(ge=1)
    request_key: str = Field(min_length=16, max_length=100)
    code: Literal['contacted', 'unreachable', 'promise', 'payment', 'documents', 'qualified', 'disburse', 'reject']
    note: str = Field(default='', max_length=1000)
    amount: int = Field(default=0, ge=0, le=1_000_000_000, strict=True)
    promise_date: str | None = None


class AgentUpdate(Input):
    capacity: int = Field(ge=1, le=100, strict=True)
    active: bool
    expected_version: int | None = Field(default=None, ge=1, strict=True)


class RegionCreate(Input):
    id: str = Field(pattern=r'^[A-Z][A-Z0-9_-]{1,7}$')
    name: str = Field(min_length=2, max_length=80)
    active: bool = True


class RegionEdit(Input):
    name: str = Field(min_length=2, max_length=80)
    active: bool
    expected_version: int = Field(ge=1, strict=True)
    reason: str = Field(min_length=10, max_length=500)


class AgentProfile(Input):
    name: str = Field(min_length=2, max_length=100)
    region_id: str = Field(min_length=1, max_length=20)
    kind: Kind
    team: Literal['A', 'B']
    channel: Literal['Tele', 'Lapangan']
    approach: str = Field(min_length=2, max_length=100)
    capacity: int = Field(ge=1, le=100, strict=True)
    active: bool = True


class AgentCreate(AgentProfile):
    id: str = Field(pattern=r'^[A-Z][A-Z0-9_-]{1,39}$')
    username: str = Field(pattern=r'^[a-z0-9][a-z0-9._-]{2,39}$')
    password: str = Field(min_length=12, max_length=128)


class AgentEdit(AgentProfile):
    expected_version: int = Field(ge=1, strict=True)
    reason: str = Field(min_length=10, max_length=500)


class OverrideInput(ReassignRequest):
    agent_id: str = Field(min_length=1, max_length=40)
    request_key: str = Field(min_length=16, max_length=100)
    expected_scoring_revision: int | None = Field(default=None,ge=0,strict=True)
    expected_policy_revision: int | None = Field(default=None,ge=0,strict=True)
