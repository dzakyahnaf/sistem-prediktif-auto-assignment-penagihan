"""Train-only descriptive clustering; portable JSON serving without sklearn."""
from collections import Counter
import math
from .historical import content_hash
from .model_engine import transformed_features

FORMAT='kmeans-json-v1'

def segment_infer(model,features,check_domain=True):
    full=transformed_features(model['preprocessor'],features,check_domain)
    values=[full[i] for i in model.get('vector_indices',range(len(full)))]
    centers=model['centers']
    if not 2<=len(centers)<=4 or any(len(c)!=len(values) or not all(math.isfinite(v) for v in c) for c in centers):
        raise ValueError('Pusat segmen tidak valid.')
    distances=[sum((a-b)**2 for a,b in zip(values,c)) for c in centers]
    index=min(range(len(centers)),key=lambda i:(distances[i],i))
    return dict(segment=f'S{index+1}',distance=round(math.sqrt(distances[index]),4),profile=model['profiles'][index])

def train_segments(artifact,samples):
    import numpy as np
    from sklearn.cluster import KMeans
    from sklearn.metrics import silhouette_score,adjusted_rand_score
    from threadpoolctl import threadpool_limits
    models,report={},[]
    def silhouette(x,labels):
        if len(set(labels))<2 or len(set(labels))>=len(labels):return None
        try:return float(silhouette_score(x,labels,sample_size=min(1000,len(x)),random_state=0))
        except ValueError:return None
    with threadpool_limits(limits=1):
        for key,pre in artifact['models'].items():
            rows={s:[r for r in samples if r['kind']==pre['kind'] and r['stage']==pre['stage'] and r['split']==s and not r['exclusion']] for s in ('train','validation','test')}
            if len(rows['train'])<40:raise ValueError('Minimal 40 sampel train untuk tiap domain/tahap.')
            names=list(pre['numeric'])+[n for n,cats in zip(pre['categorical'],pre['categories']) for _ in cats]
            selected=[i for i,n in enumerate(names) if n not in {'region_id','decision_month','decision_weekday'}]
            x={s:np.asarray([[transformed_features(pre,r['features'],False)[i] for i in selected] for r in rr]) for s,rr in rows.items()}
            options=[]
            for k in (2,3,4):
                fit=KMeans(n_clusters=k,n_init=10,random_state=0).fit(x['train'])
                score=silhouette(x['train'],fit.labels_)
                if score is not None and min(Counter(fit.labels_).values())>=5:options.append((score,k,fit))
            if not options:raise ValueError('Pemisahan cluster tidak memadai.')
            score,k,fit=max(options,key=lambda t:(t[0],-t[1]))
            order=sorted(range(k),key=lambda i:tuple(fit.cluster_centers_[i]));centers=fit.cluster_centers_[order].tolist()
            stable=[]
            for seed in (1,2,3):
                rng=np.random.default_rng(seed);indices=rng.choice(len(x['train']),size=max(30,int(len(x['train'])*.8)),replace=False)
                other=KMeans(n_clusters=k,n_init=10,random_state=seed).fit(x['train'][indices])
                stable.append(float(adjusted_rand_score(fit.labels_,other.predict(x['train']))))
            profiles=[]
            for i in order:
                group=[r for r,l in zip(rows['train'],fit.labels_) if l==i]
                means={n:round(float(np.mean([r['features'][n] for r in group])),3) for n in pre['numeric'] if n not in {'decision_month','decision_weekday'}}
                categories={n:dict(Counter(r['features'][n] for r in group)) for n in pre['categorical'] if n!='region_id'}
                profiles.append(dict(n=len(group),means=means,categories=categories))
            fields=('kind','stage','feature_names','numeric','categorical','medians','means','scales','categories','bounds')
            model=dict(preprocessor={n:pre[n] for n in fields},vector_indices=selected,centers=centers,profiles=profiles)
            # Validate the JSON nearest-center path against sklearn before persisting.
            mapping={old:new for new,old in enumerate(order)}
            for r,pred in zip(rows['train'],fit.labels_):
                assert segment_infer(model,r['features'],False)['segment']==f'S{mapping[pred]+1}'
            subsets={}
            for split in rows:
                labels=fit.predict(x[split]) if len(x[split]) else []
                subsets[split]=dict(n=len(labels),silhouette=silhouette(x[split],labels) if len(labels) else None,
                    counts={f'S{mapping[int(i)]+1}':int(n) for i,n in Counter(labels).items()})
            models[key]=model
            warnings=[]
            for split,s in subsets.items():
                if len(s['counts'])<2:warnings.append(f'{split}: seluruh sampel jatuh pada satu segmen; silhouette tidak tersedia.')
                elif s['silhouette'] is not None and s['silhouette']<.1:warnings.append(f'{split}: pemisahan segmen lemah (silhouette<0,1).')
            if min(stable)<.8:warnings.append('Stabilitas resampling ARI di bawah0,8; perlu review.')
            report.append(dict(key=key,k=k,features=sorted(set(names[i] for i in selected)),warnings=warnings,selection='train silhouette',train_candidates=[dict(k=k_,silhouette=s) for s,k_,_ in options],
                stability_ari=stable,subsets=subsets,profiles=[dict(segment=f'S{i+1}',**p) for i,p in enumerate(profiles)]))
    return dict(format=FORMAT,source_provenance=artifact['provenance'],models=models),dict(models=report,
        warning='Segmen deskriptif sintetis; ID S1 dst bukan urutan risiko, bukan diagnosis atau bukti petugas terbaik. Stabilitas resampling bukan validasi bisnis.')

def decision_segment(conn,prediction,release_id):
    if not release_id:return dict(status='inactive',reason='Belum ada paket segmen dipilih.')
    try:
        import json
        row=conn.execute('SELECT * FROM segment_releases WHERE id=?',(release_id,)).fetchone()
        if row is None:raise ValueError('Paket segmen tidak ditemukan.')
        artifact=json.loads(row['artifact'])
        if artifact.get('format')!=FORMAT or content_hash(artifact)!=row['artifact_sha256']:raise ValueError('Checksum segmen tidak valid.')
        if not prediction['features']:raise ValueError('Snapshot sebelum keputusan belum tersedia.')
        result=segment_infer(artifact['models'][prediction['model_key']],prediction['features'])
        return dict(status='ready',release_id=release_id,**result,
            reason='Kelompok kemiripan fitur sebelum keputusan; bukan probabilitas atau urutan risiko.')
    except (ValueError,KeyError,TypeError,IndexError,OverflowError) as exc:return dict(status='unavailable',release_id=release_id,reason=str(exc))
