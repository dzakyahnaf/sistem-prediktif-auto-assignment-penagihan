"""Versioned policy and descriptive segments; preserve all earlier decisions."""
from alembic import op
import sqlalchemy as sa
from migrations.schema_0001 import metadata as baseline
from migrations.schema_0004 import define_decisions
revision = '0004_decisions'
down_revision = '0003_models'
branch_labels = None
depends_on = None

def upgrade():
    m = sa.MetaData(naming_convention=baseline.naming_convention)
    for n in ('users','ml_releases'): sa.Table(n,m,sa.Column('id',sa.Text,primary_key=True))
    define_decisions(m)
    for t in m.sorted_tables:
        if t.name in {'segment_releases','policy_revisions'}: t.create(op.get_bind())

def downgrade():
    raise RuntimeError('Preserve policy/segment history; restore a backup separately.')
