"""Portable SQLAlchemy Core schema. UTC ISO timestamps and integer money retain API semantics."""
import sqlalchemy as sa

metadata = sa.MetaData(naming_convention={'ix':'ix_%(table_name)s_%(column_0_name)s', 'uq':'uq_%(table_name)s_%(column_0_name)s',
    'ck':'ck_%(table_name)s_%(constraint_name)s', 'fk':'fk_%(table_name)s_%(column_0_name)s_%(referred_table_name)s', 'pk':'pk_%(table_name)s'})

def txt(name, *, pk=False, nullable=False, default=None, fk=None, unique=False):
    return sa.Column(name, sa.Text, *([sa.ForeignKey(fk)] if fk else []), primary_key=pk, nullable=nullable,
                     server_default=sa.text("'"+default+"'") if default is not None else None, unique=unique)
def num(name, default=None):
    return sa.Column(name, sa.Integer, nullable=False, server_default=sa.text(str(default)) if default is not None else None)
def ident(): return sa.Column('id', sa.Integer, primary_key=True, autoincrement=True)

regions = sa.Table('regions',metadata,txt('id',pk=True),txt('name'),num('active',1),num('version',1))
agents = sa.Table('agents',metadata,txt('id',pk=True),txt('name'),txt('region_id',fk='regions.id'),txt('kind'),txt('team'),txt('channel'),txt('approach'),
    num('capacity'),num('active',1),num('version',1),sa.CheckConstraint('capacity > 0',name='capacity_positive'))
users = sa.Table('users',metadata,txt('id',pk=True),txt('username',unique=True),txt('password_hash'),txt('role'),txt('agent_id',fk='agents.id',nullable=True))
sessions = sa.Table('sessions',metadata,txt('token_hash',pk=True),txt('user_id',fk='users.id'),txt('expires_at'))
cases = sa.Table('cases',metadata,txt('id',pk=True),txt('kind'),txt('customer'),txt('region_id',fk='regions.id'),txt('difficulty'),num('amount'),num('paid',0),
    num('dpd',0),num('income',0),num('interest',0),num('documents_complete',0),txt('status',default='new'),num('cycle',0),
    txt('agent_id',fk='agents.id',nullable=True),txt('assigned_at',nullable=True),txt('due_at',nullable=True),txt('created_at'),
    sa.Column('score',sa.Float,nullable=False),txt('score_version'),txt('source',default='synthetic'),num('version',1),sa.CheckConstraint('amount > 0',name='amount_positive'))
assignments = sa.Table('assignments',metadata,ident(),txt('case_id',fk='cases.id'),txt('agent_id',fk='agents.id'),num('cycle'),txt('assigned_at'),txt('due_at'),
    txt('ended_at',nullable=True),txt('outcome',nullable=True),sa.Column('score',sa.Float,nullable=False),txt('reason'),txt('actor_id',fk='users.id'),
    txt('agent_name',nullable=True),txt('agent_team',nullable=True),txt('agent_channel',nullable=True),sa.UniqueConstraint('case_id','cycle'))
activities = sa.Table('activities',metadata,ident(),txt('case_id',fk='cases.id'),sa.Column('assignment_id',sa.Integer,sa.ForeignKey('assignments.id'),nullable=False),
    txt('actor_id',fk='users.id'),txt('code'),txt('note'),num('amount',0),txt('promise_date',nullable=True),txt('created_at'),txt('request_key',unique=True))
audit = sa.Table('audit',metadata,ident(),txt('actor_id',fk='users.id'),txt('action'),txt('case_id',nullable=True),txt('detail'),txt('created_at'))
import_batches = sa.Table('import_batches',metadata,txt('id',pk=True),txt('actor_id',fk='users.id'),txt('kind'),txt('filename'),txt('file_sha256'),
    sa.Column('content',sa.LargeBinary),txt('created_at'),txt('expires_at'),txt('state',default='uploaded'),num('revision',0),txt('metadata'),
    txt('preview',nullable=True),txt('result',nullable=True),num('upload_order',0))
import_case_refs = sa.Table('import_case_refs',metadata,txt('kind',pk=True),txt('source_key',pk=True),txt('source_ref'),txt('case_id',unique=True,fk='cases.id'),txt('batch_id',fk='import_batches.id'))
assignment_overrides = sa.Table('assignment_overrides',metadata,txt('request_key',pk=True),txt('actor_id',fk='users.id'),txt('case_id',fk='cases.id'),txt('payload'),txt('result'),txt('created_at'))
migration_receipts = sa.Table('migration_receipts',metadata,txt('source_sha256',pk=True),txt('created_at'),txt('manifest'))
sa.Index('ix_cases_queue',cases.c.kind,cases.c.status,cases.c.region_id)
sa.Index('ix_assignments_agent_time',assignments.c.agent_id,assignments.c.assigned_at)
sa.Index('ix_activities_case',activities.c.case_id,activities.c.id)
sa.Index('ix_import_batches_actor',import_batches.c.actor_id,import_batches.c.created_at)

from .analytic_schema import define_analytics
define_analytics(metadata)
from .model_schema import define_models
define_models(metadata)
from .decision_schema import define_decisions
define_decisions(metadata)
from .operation_schema import define_operations
define_operations(metadata)
from .hardening_schema import define_hardening
define_hardening(metadata)
