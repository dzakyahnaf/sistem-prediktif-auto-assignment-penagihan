"""Portable baseline; adopt legacy SQLite v3 while preserving business columns."""
from alembic import op
import sqlalchemy as sa
from migrations.schema_0001 import metadata
revision='0001_portable'
down_revision=None
branch_labels=None
depends_on=None

def upgrade():
    conn=op.get_bind()
    metadata.create_all(conn,checkfirst=True)
    if 'upload_order' not in {c['name'] for c in sa.inspect(conn).get_columns('import_batches')}:
        op.add_column('import_batches',sa.Column('upload_order',sa.Integer,nullable=False,server_default='0'))
        rows=conn.exec_driver_sql('SELECT id FROM import_batches ORDER BY rowid').fetchall()
        for i,row in enumerate(rows,1): conn.execute(sa.text('UPDATE import_batches SET upload_order=:n WHERE id=:id'),dict(n=i,id=row[0]))

def downgrade():
    raise RuntimeError('Destructive baseline downgrade disabled. Restore a verified backup to a separate database.')
