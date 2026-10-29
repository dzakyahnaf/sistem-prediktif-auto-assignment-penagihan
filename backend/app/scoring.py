"""Point-in-time operational serving, explicit fallback and decision provenance."""
import json
from .domain import MODEL_VERSION, TERMINAL, score_case, timestamp
from .historical import FEATURE_VERSION, content_hash, encode, snapshot_features
from .model_engine import ENGINE, infer, explain
from .policy import current_policy,rule_version,snapshot_policy
from .segments import decision_segment


def capture_origin(conn, case):
    # Called only at actual creation, never backfilled from mutable legacy cases.
    conn.execute('INSERT INTO case_origins(case_id,payload) VALUES (?,?)', (case['id'],encode({
        k:case[k] for k in ('id','kind','created_at','region_id','difficulty','amount','dpd','income','interest','documents_complete')})))


def serving_state(conn):
    row = conn.execute("SELECT * FROM ml_serving WHERE id='default'").fetchone()
    return dict(row) if row else dict(id='default',release_id=None,revision=0,updated_at=None)


def valid_artifact(row):
    artifact = json.loads(row['artifact'])
    if content_hash(artifact)!=row['artifact_sha256'] or artifact.get('format')!=ENGINE or artifact.get('feature_version')!=FEATURE_VERSION:
        raise ValueError('Artefak/checksum/versi fitur model tidak valid.')
    return artifact


def decision_score(conn, case, now, closing_current=False):
    stage = 'initial' if case['cycle']==0 else 'reassignment'
    key = case['kind']+'_'+stage
    state = serving_state(conn)
    policy = current_policy(conn)
    previous = [dict(r) for r in conn.execute('SELECT * FROM assignments WHERE case_id=? ORDER BY cycle',(case['id'],))]
    usable = [p for p in previous if p['ended_at'] and p['ended_at']<=timestamp(now)]
    if closing_current:
        usable += [{**p,'ended_at':timestamp(now)} for p in previous if p['ended_at'] is None]
    events = []
    for p in usable:
        events += [dict(at=r['created_at'],code=r['code'],amount=r['amount']) for r in conn.execute(
            'SELECT created_at,code,amount FROM activities WHERE assignment_id=? AND created_at<=? ORDER BY id',(p['id'],timestamp(now)))]
    if stage=='reassignment':
        last = usable[-1] if usable else None
        codes = [r[0] for r in conn.execute('SELECT code FROM activities WHERE assignment_id=?', (last['id'],))] if last else []
        rules = score_case(case,codes,policy['config'])[0]
    else: rules = score_case(case,policy=policy['config'])[0]
    result = dict(source='rules',version=rule_version(policy['revision']),score=rules,probability=None,model_key=key,
        release_id=None,serving_revision=state['revision'],decision_at=timestamp(now),feature_max_at=None,
        features={},reason='Belum ada model aktif.',horizon=None,horizon_unit=None)
    origin = conn.execute('SELECT payload FROM case_origins WHERE case_id=?',(case['id'],)).fetchone()
    if origin:
        try:
            f, available = snapshot_features(json.loads(origin[0]),now,
                [dict(closed_at=p['ended_at']) for p in usable],events,stage)
            result.update(features=f,feature_max_at=available)
        except (ValueError,KeyError,TypeError):
            origin=None
            result['reason']='Fallback rules: snapshot fitur tidak valid.'
    if not state['release_id']: return result
    try:
        if not origin: raise ValueError('Snapshot sebelum keputusan tidak tersedia pada kasus lama.')
        if result['feature_max_at']>timestamp(now): raise ValueError('Waktu fitur melewati keputusan.')
        row = conn.execute('SELECT * FROM ml_releases WHERE id=?',(state['release_id'],)).fetchone()
        if row is None: raise ValueError('Versi model aktif tidak ditemukan.')
        artifact = valid_artifact(row)
        if not json.loads(row['report'])['activation_eligible']: raise ValueError('Model tidak memenuhi pemeriksaan demo.')
        model = artifact['models'][key]
        probability = infer(model,result['features'])
        horizon = artifact['provenance']['collection_hours' if case['kind']=='collection' else 'origination_days']
        result.update(source='ml_simulation',version=row['id']+':'+key,release_id=row['id'],
            score=round(probability*100,2),probability=probability,reason='Prediksi model yang dilatih pada data sintetis.',
            horizon=horizon,horizon_unit='hours' if case['kind']=='collection' else 'days')
        result['explanation']=explain(model,result['features'])
    except (ValueError,KeyError,TypeError,ZeroDivisionError,OverflowError) as exc:
        result['reason']='Fallback rules: '+str(exc)
    return result


def assignment_preview(conn, case, now, closing_current=False):
    prediction = decision_score(conn,case,now,closing_current)
    prediction['policy']=snapshot_policy(conn,case['kind'],now)
    prediction['segment']=decision_segment(conn,prediction,prediction['policy']['config']['segment_release_id'])
    return {**case,'score':prediction['score'],'score_version':prediction['version'],
        'medium_threshold':prediction['policy']['config']['medium_threshold']},prediction


def recorded_prediction(conn, case):
    row = conn.execute('SELECT payload FROM ml_predictions WHERE case_id=? AND cycle=?',(case['id'],case['cycle'])).fetchone()
    return json.loads(row[0]) if row else None
