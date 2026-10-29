"""Loopback-only demo bundle. Database always belongs to this extracted bundle."""
import argparse,hashlib,json,os,sys
from pathlib import Path

ROOT=Path(__file__).resolve().parent

def verify():
    manifest=json.loads((ROOT/'manifest.json').read_text(encoding='utf-8'))
    for name,expected in manifest['files'].items():
        target=(ROOT/name).resolve()
        if not target.is_relative_to(ROOT) or not target.is_file() or hashlib.sha256(target.read_bytes()).hexdigest()!=expected:
            raise ValueError('Bundle checksum mismatch: '+name)
    return manifest

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--port',type=int,default=8080);p.add_argument('--check',action='store_true');a=p.parse_args()
    if not 1024<=a.port<=65535:p.error('Choose a port from 1024 to 65535.')
    m=verify();print('Assignment Studio '+m['version']+'; bundle checksums verified.',flush=True)
    if a.check:return
    runtime=ROOT/'runtime';runtime.mkdir(exist_ok=True)
    os.environ.pop('DATABASE_URL',None)
    os.environ['DATABASE_PATH']=str(runtime/'demo.db')
    os.environ['WEB_BUILD_PATH']=str(ROOT/'web')
    sys.path.insert(0,str(ROOT/'backend'))
    import uvicorn
    uvicorn.run('app.main:app',host='127.0.0.1',port=a.port,proxy_headers=False)

if __name__=='__main__':main()
