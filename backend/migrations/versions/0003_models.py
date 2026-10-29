"""Model registry/lifecycle and point-in-time operational snapshots."""
from alembic import op
import sqlalchemy as sa
from migrations.schema_0001 import metadata as baseline
from migrations.schema_0003 import define_models

revision = '0003_models'
down_revision = '0002_analytics'
branch_labels = None
depends_on = None


def upgrade():
    metadata = sa.MetaData(naming_convention=baseline.naming_convention)
    for name in ('users', 'cases', 'analytics_runs'):
        sa.Table(name, metadata, sa.Column('id', sa.Text, primary_key=True))
    define_models(metadata)
    for table in metadata.sorted_tables:
        if table.name.startswith('ml_') or table.name == 'case_origins': table.create(op.get_bind())


def downgrade():
    raise RuntimeError('Preserve model/decision history; restore a backup to a separate database.')
