"""Versioned policy and immutable descriptive segmentation packages."""
import sqlalchemy as sa

def define_decisions(metadata):
    def txt(name, **kw): return sa.Column(name, sa.Text, nullable=False, **kw)
    sa.Table('segment_releases', metadata, txt('id', primary_key=True), txt('request_key', unique=True),
        sa.Column('model_id', sa.Text, sa.ForeignKey('ml_releases.id'), nullable=False),
        sa.Column('actor_id', sa.Text, sa.ForeignKey('users.id'), nullable=False),
        txt('created_at'), txt('artifact'), txt('artifact_sha256'), txt('report'))
    sa.Table('policy_revisions', metadata, sa.Column('revision', sa.Integer, primary_key=True, autoincrement=False),
        txt('request_key', unique=True), sa.Column('actor_id', sa.Text, sa.ForeignKey('users.id'), nullable=False),
        txt('config'), txt('reason'), txt('created_at'))
