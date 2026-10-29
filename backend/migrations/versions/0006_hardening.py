"""Persistent failed-login budgets, no rewrite of existing business data."""
from alembic import op
import sqlalchemy as sa
from migrations.schema_0001 import metadata as baseline
from migrations.schema_0006 import define_hardening
revision='0006_hardening'
down_revision='0005_operations'
branch_labels=None
depends_on=None
def upgrade():
    m=sa.MetaData(naming_convention=baseline.naming_convention);define_hardening(m)
    m.create_all(op.get_bind())
def downgrade():raise RuntimeError('Restore a backup separately; preserve login protection state.')
