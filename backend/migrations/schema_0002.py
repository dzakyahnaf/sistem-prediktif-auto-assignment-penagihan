"""Historical datasets are isolated from operational cases/assignments."""
import sqlalchemy as sa


def define_analytics(metadata):
    def text(name, **kw): return sa.Column(name, sa.Text, nullable=False, **kw)
    sa.Table('analytics_runs', metadata,
        text('id', primary_key=True), text('request_key', unique=True),
        sa.Column('actor_id', sa.Text, sa.ForeignKey('users.id'), nullable=False),
        text('created_at'), text('config'), text('manifest'), text('data_sha256'))
    for name in ('cases', 'decisions', 'events', 'samples'):
        columns = [sa.Column('run_id', sa.Text, sa.ForeignKey('analytics_runs.id'), primary_key=True),
                   text('record_id', primary_key=True), text('payload')]
        if name == 'samples':
            columns += [text('kind'), text('stage'), text('split')]
        sa.Table('analytics_' + name, metadata, *columns)
    sa.Index('ix_analytics_samples_filter', metadata.tables['analytics_samples'].c.run_id,
             metadata.tables['analytics_samples'].c.kind, metadata.tables['analytics_samples'].c.stage,
             metadata.tables['analytics_samples'].c.split)
