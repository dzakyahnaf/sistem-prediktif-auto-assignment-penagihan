"""Add immutable analytical history; existing operational data is untouched."""
from alembic import op
import sqlalchemy as sa
from migrations.schema_0002 import define_analytics
from migrations.schema_0001 import metadata as baseline

revision = '0002_analytics'
down_revision = '0001_portable'
branch_labels = None
depends_on = None


def upgrade():
    metadata = sa.MetaData(naming_convention=baseline.naming_convention)
    sa.Table('users', metadata, sa.Column('id', sa.Text, primary_key=True))
    define_analytics(metadata)
    for table in metadata.sorted_tables:
        if table.name.startswith('analytics_'):
            table.create(op.get_bind())


def downgrade():
    raise RuntimeError('Restore a backup to a separate database; analytical history must be preserved.')
