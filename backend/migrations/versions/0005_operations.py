"""Add notification, mock outbox and account lifecycle without rewriting users."""
from alembic import op
import sqlalchemy as sa
from migrations.schema_0001 import metadata as baseline
from migrations.schema_0005 import define_operations
revision='0005_operations'
down_revision='0004_decisions'
branch_labels=None
depends_on=None
def upgrade():
    m=sa.MetaData(naming_convention=baseline.naming_convention)
    for n in ('users','cases'):sa.Table(n,m,sa.Column('id',sa.Text,primary_key=True))
    define_operations(m)
    for t in m.sorted_tables:
        if t.name not in {'users','cases'}:t.create(op.get_bind())
def downgrade():raise RuntimeError('Preserve operational history; restore a backup separately.')
