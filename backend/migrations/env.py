import os
from alembic import context
from sqlalchemy import create_engine, pool
from app.tables import metadata

def run(connection):
    context.configure(connection=connection,target_metadata=metadata,compare_type=True)
    with context.begin_transaction(): context.run_migrations()

connection=context.config.attributes.get('connection')
if connection is not None: run(connection)
else:
    url=os.environ.get('DATABASE_URL')
    if not url: raise RuntimeError('Set DATABASE_URL for Alembic CLI; never store credentials in alembic.ini.')
    with create_engine(url,poolclass=pool.NullPool,hide_parameters=True).begin() as connection:
        if connection.dialect.name=='postgresql': connection.exec_driver_sql('SELECT pg_advisory_xact_lock(739102602)')
        run(connection)
