"""Local notifications, mock integration outbox and account controls."""
import sqlalchemy as sa

def define_operations(m):
    def txt(n,nullable=False,**kw):return sa.Column(n,sa.Text,nullable=nullable,**kw)
    def num(n):return sa.Column(n,sa.Integer,nullable=False)
    sa.Table('user_controls',m,sa.Column('user_id',sa.Text,sa.ForeignKey('users.id'),primary_key=True),num('active'),num('version'),txt('updated_at'))
    sa.Table('notifications',m,txt('id',primary_key=True),txt('event_key',unique=True),
        sa.Column('user_id',sa.Text,sa.ForeignKey('users.id'),nullable=False),
        sa.Column('case_id',sa.Text,sa.ForeignKey('cases.id')),txt('title'),txt('body'),txt('created_at'),txt('read_at',nullable=True))
    sa.Index('ix_notifications_user',m.tables['notifications'].c.user_id,m.tables['notifications'].c.created_at)
    sa.Table('integration_jobs',m,txt('id',primary_key=True),txt('request_key',unique=True),
        sa.Column('actor_id',sa.Text,sa.ForeignKey('users.id'),nullable=False),
        sa.Column('case_id',sa.Text,sa.ForeignKey('cases.id'),nullable=False),num('cycle'),txt('channel'),txt('scenario'),
        txt('state'),num('attempts'),num('attempt_limit'),num('version'),txt('available_at'),txt('created_at'),txt('updated_at'),txt('receipt_id',nullable=True,unique=True))
    sa.Table('integration_attempts',m,sa.Column('job_id',sa.Text,sa.ForeignKey('integration_jobs.id'),primary_key=True),
        sa.Column('attempt',sa.Integer,primary_key=True),txt('state'),txt('detail'),txt('created_at'))
    sa.Table('operation_requests',m,txt('request_key',primary_key=True),
        sa.Column('actor_id',sa.Text,sa.ForeignKey('users.id'),nullable=False),txt('operation'),txt('payload'),txt('result'),txt('created_at'),txt('secret_hash',nullable=True))
