"""Model releases, serving transitions and immutable decision snapshots."""
import sqlalchemy as sa


def define_models(metadata):
    def txt(name, **kw): return sa.Column(name, sa.Text, nullable=False, **kw)
    sa.Table('ml_releases', metadata, txt('id', primary_key=True), txt('request_key', unique=True),
        sa.Column('run_id', sa.Text, sa.ForeignKey('analytics_runs.id'), nullable=False),
        sa.Column('actor_id', sa.Text, sa.ForeignKey('users.id'), nullable=False),
        txt('created_at'), txt('report'), txt('artifact'), txt('artifact_sha256'))
    sa.Table('ml_serving', metadata, txt('id', primary_key=True),
        sa.Column('release_id', sa.Text, sa.ForeignKey('ml_releases.id')),
        sa.Column('revision', sa.Integer, nullable=False), txt('updated_at'))
    sa.Table('ml_transitions', metadata, txt('request_key', primary_key=True),
        sa.Column('actor_id', sa.Text, sa.ForeignKey('users.id'), nullable=False),
        txt('payload'), txt('result'), txt('created_at'))
    sa.Table('case_origins', metadata,
        sa.Column('case_id', sa.Text, sa.ForeignKey('cases.id'), primary_key=True), txt('payload'))
    sa.Table('ml_predictions', metadata,
        sa.Column('case_id', sa.Text, sa.ForeignKey('cases.id'), primary_key=True),
        sa.Column('cycle', sa.Integer, primary_key=True), txt('payload'))
