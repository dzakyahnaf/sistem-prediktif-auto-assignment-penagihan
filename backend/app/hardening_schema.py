"""Failed-login state contains hashed buckets only, no credentials or raw IP."""
import sqlalchemy as sa

def define_hardening(m):
    sa.Table('login_failures',m,sa.Column('bucket',sa.Text,primary_key=True),
        sa.Column('failures',sa.Integer,nullable=False),sa.Column('started_at',sa.Text,nullable=False))
