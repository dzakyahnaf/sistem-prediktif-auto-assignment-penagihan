"""Train-only preprocessing, held-out calibration selection and portable JSON logit.

The test split is evaluated after every fitted/selected parameter is frozen.
Serving uses only JSON and math; no pickle or executable model deserialization.
"""
import math
import warnings
from collections import Counter
from .historical import FEATURES, FEATURE_VERSION, VERSION, content_hash
from .domain import score_case

ENGINE = 'logit-json-v1'


def sigmoid(z):
    return 1/(1+math.exp(-max(-700, min(700, z))))


def transformed_features(model, features, check_domain=True):
    expected = FEATURES[model['kind']][model['stage']]
    if model['feature_names'] != expected or set(features) != set(expected):
        raise ValueError('Kontrak fitur tidak cocok.')
    values = []
    for i, name in enumerate(model['numeric']):
        value = features[name]
        value = model['medians'][i] if value is None else float(value)
        if not math.isfinite(value): raise ValueError('Fitur numerik tidak valid.')
        low, high = model['bounds'][i]
        if check_domain and not low-1e-8 <= value <= high+1e-8:
            raise ValueError('Fitur di luar rentang data latih: '+name)
        values.append((value-model['means'][i])/model['scales'][i])
    for name, categories in zip(model['categorical'], model['categories']):
        if check_domain and features[name] not in categories: raise ValueError('Kategori belum dikenal: '+name)
        values.extend(float(features[name] == category) for category in categories)
    if len(values) > 64: raise ValueError('Dimensi model tidak valid.')
    return values


def infer(model, features, check_domain=True):
    values = transformed_features(model, features, check_domain)
    if len(values) != len(model['coef']): raise ValueError('Dimensi model tidak valid.')
    numbers = [*model['coef'], model['intercept'], model['calibration']['slope'], model['calibration']['intercept'], *model['means'], *model['scales']]
    if not all(math.isfinite(v) for v in numbers) or any(v <= 0 for v in model['scales']): raise ValueError('Parameter model tidak valid.')
    raw = model['intercept'] + sum(c*v for c,v in zip(model['coef'], values))
    return sigmoid(model['calibration']['slope']*raw+model['calibration']['intercept'])


def explain(model, features):
    values = transformed_features(model, features)
    names = list(model['numeric']) + [n for n,cats in zip(model['categorical'],model['categories']) for _ in cats]
    grouped = {}
    for name,value,coef in zip(names,values,model['coef']): grouped[name]=grouped.get(name,0)+value*coef
    return [dict(feature=n, contribution=round(v,6)) for n,v in sorted(grouped.items(),key=lambda e:(-abs(e[1]),e[0]))[:4]]


def metrics(y, probabilities):
    import numpy as np
    from sklearn.metrics import roc_auc_score, average_precision_score, log_loss, confusion_matrix
    if not len(y): return None
    p = np.asarray(probabilities, dtype=float); y = np.asarray(y, dtype=int)
    p = np.clip(p, 1e-12, 1-1e-12)
    both = len(set(y)) == 2
    bins = []
    for index in range(5):
        mask = (p >= index/5) & ((p < (index+1)/5) if index < 4 else (p <= 1))
        if mask.any(): bins.append(dict(bin=index, count=int(mask.sum()), predicted=float(p[mask].mean()), observed=float(y[mask].mean())))
    return dict(n=len(y), positive=int(y.sum()), auc=float(roc_auc_score(y,p)) if both else None,
        average_precision=float(average_precision_score(y,p)) if both else None,
        brier=float(np.mean((p-y)**2)), log_loss=float(log_loss(y,p,labels=[0,1])),
        ece=sum(b['count']*abs(b['predicted']-b['observed']) for b in bins)/len(y),
        confusion=confusion_matrix(y,p>=.5,labels=[0,1]).tolist(), reliability=bins)


def calibration_partitions(validation):
    ordered = sorted(validation, key=lambda s:(s['decision_at'],s['id']))
    half = len(ordered)//2
    first, last = ordered[:half], ordered[half:]
    overlap = {s['entity_id'] for s in first} & {s['entity_id'] for s in last}
    return [s for s in first if s['entity_id'] not in overlap], [s for s in last if s['entity_id'] not in overlap], len(overlap)


def class_counts(rows):
    return dict(Counter(str(s['label']) for s in rows))


def rule_indices(rows):
    indices = []
    for row in rows:
        f = row['features']
        case = dict(kind=row['kind'], **f)
        codes = [code for code,field in [('unreachable','previous_unreachable'),('promise','previous_promises')] if f.get(field,0)>0]
        indices.append(score_case(case,codes)[0]/100)
    return indices


def train_release(samples, provenance):
    import numpy as np
    import scipy
    import sklearn
    from sklearn.compose import ColumnTransformer
    from sklearn.pipeline import make_pipeline
    from sklearn.impute import SimpleImputer
    from sklearn.preprocessing import StandardScaler, OneHotEncoder
    from sklearn.linear_model import LogisticRegression
    from sklearn.exceptions import ConvergenceWarning
    from sklearn.metrics import roc_auc_score, average_precision_score
    from threadpoolctl import threadpool_limits

    artifact = dict(format=ENGINE, feature_version=FEATURE_VERSION, simulator_version=VERSION,
        provenance=provenance, models={})
    report = dict(engine=ENGINE, libraries=dict(sklearn=sklearn.__version__,numpy=np.__version__,scipy=scipy.__version__),
        source='synthetic-only', models=[], activation_eligible=True,
        warnings=['Evaluasi simulator; bukan validasi nasabah nyata atau bukti uplift kausal.',
            'Test tidak dipakai memilih parameter/kalibrasi. Sampel kecil membatasi kepastian metrik.',
            'Aktivasi hanya untuk demo. Low/High dan hard constraint assignment tetap berlaku.',
            'Rules adalah indeks: dibandingkan sebagai ranking, bukan sebagai probabilitas terkalibrasi.'])
    for kind in FEATURES:
        for stage in ('initial','reassignment'):
            key = kind+'_'+stage
            rows = [s for s in samples if s['kind']==kind and s['stage']==stage and s['split']!='excluded']
            partitions = {p:[s for s in rows if s['split']==p] for p in ('train','validation','test')}
            if any(min(Counter(s['label'] for s in part).get(c,0) for c in (0,1))<20 for part in partitions.values()):
                raise ValueError('Minimal 20 label tiap kelas/partisi belum terpenuhi: '+key)
            train, validation, test = (partitions[p] for p in ('train','validation','test'))
            calibration, selection, purged = calibration_partitions(validation)
            fields = FEATURES[kind][stage]
            categorical = ['region_id','difficulty']; numeric = [f for f in fields if f not in categorical]
            matrix = lambda part: np.asarray([[s['features'][f] for f in fields] for s in part], dtype=object)
            labels = lambda part: np.asarray([s['label'] for s in part],dtype=int)
            pre = ColumnTransformer([
                ('numeric',make_pipeline(SimpleImputer(strategy='median',keep_empty_features=True),StandardScaler()),[fields.index(f) for f in numeric]),
                ('categorical',OneHotEncoder(handle_unknown='ignore',sparse_output=False),[fields.index(f) for f in categorical]),
            ],sparse_threshold=0)
            clf = LogisticRegression(C=1.0,solver='lbfgs',max_iter=1000,tol=1e-7,random_state=0)
            with threadpool_limits(limits=1), warnings.catch_warnings():
                warnings.simplefilter('error',ConvergenceWarning)
                x = pre.fit_transform(matrix(train)); clf.fit(x,labels(train))
            imp, scaler = pre.named_transformers_['numeric'].steps[0][1], pre.named_transformers_['numeric'].steps[1][1]
            encoder = pre.named_transformers_['categorical']
            imputed = imp.transform(matrix(train)[:,[fields.index(f) for f in numeric]])
            model = dict(kind=kind,stage=stage,feature_names=fields,numeric=numeric,categorical=categorical,
                medians=imp.statistics_.tolist(),means=scaler.mean_.tolist(),scales=scaler.scale_.tolist(),
                bounds=[[float(imputed[:,i].min()),float(imputed[:,i].max())] for i in range(len(numeric))],
                categories=[c.tolist() for c in encoder.categories_],coef=clf.coef_[0].tolist(),intercept=float(clf.intercept_[0]),
                calibration=dict(method='none',slope=1.0,intercept=0.0))
            uncalibrated_selection = metrics(labels(selection),[infer(model,s['features'],False) for s in selection])
            attempted = all(min(Counter(s['label'] for s in part).get(c,0) for c in (0,1))>=5 for part in (calibration,selection))
            calibration_score = None
            if attempted:
                scores = clf.decision_function(pre.transform(matrix(calibration))).reshape(-1,1)
                with threadpool_limits(limits=1):
                    cal = LogisticRegression(C=1.0,solver='lbfgs',max_iter=1000,tol=1e-7).fit(scores,labels(calibration))
                calibrated = {**model,'calibration':dict(method='sigmoid-validation',slope=float(cal.coef_[0,0]),intercept=float(cal.intercept_[0]))}
                calibration_score = metrics(labels(selection),[infer(calibrated,s['features'],False) for s in selection])
                if cal.coef_[0,0]>0 and calibration_score['log_loss']+1e-6 < uncalibrated_selection['log_loss']:
                    model = calibrated
            # Verify JSON inference reproduces sklearn's fitted pipeline before persisting.
            raw_model = {**model,'calibration':dict(method='none',slope=1.0,intercept=0.0)}
            portable = np.asarray([infer(raw_model,s['features'],False) for s in train])
            if not np.allclose(portable,clf.predict_proba(x)[:,1],atol=1e-10): raise ValueError('JSON inference parity failed.')
            artifact['models'][key] = model
            prior = float(labels(train).mean())
            evaluation = {}
            for name, part in dict(train=train,validation_calibration=calibration,validation_selection=selection,test=test).items():
                p = [infer(model,s['features'],False) for s in part]; y = labels(part); rules = rule_indices(part)
                both = len(set(y))==2
                coverage = 0
                for s in part:
                    try: infer(model,s['features']); coverage+=1
                    except ValueError: pass
                evaluation[name] = dict(model=metrics(y,p),constant=metrics(y,[prior]*len(part)),
                    rules_ranking=dict(auc=float(roc_auc_score(y,rules)) if both else None,
                                       average_precision=float(average_precision_score(y,rules)) if both else None),
                    serving_coverage=coverage/len(part) if part else 0)
            selected_metric = evaluation['validation_selection']['model']
            baseline_metric = evaluation['validation_selection']['constant']
            report['models'].append(dict(key=key,kind=kind,stage=stage,calibration=model['calibration']['method'],
                calibration_attempted=attempted,calibration_entity_purged=purged,
                counts={p:dict(n=len(v),classes=class_counts(v)) for p,v in partitions.items()},
                selection_candidates=dict(raw=uncalibrated_selection,calibrated=calibration_score),evaluation=evaluation,
                validation_beats_constant=bool(selected_metric and selected_metric['log_loss']<baseline_metric['log_loss']),
                horizon=provenance['collection_hours'] if kind=='collection' else provenance['origination_days'],
                horizon_unit='hours' if kind=='collection' else 'days'))
    report['artifact_sha256'] = content_hash(artifact)
    return artifact, report
