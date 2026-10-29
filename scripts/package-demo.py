"""Allowlisted, checksum-manifested demo package; never bundles runtime/secrets."""
import argparse,hashlib,json,shutil,zipfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--web',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
    web=a.web.resolve();out=a.output.resolve();archive=out.parent/(out.name+'.zip')
    if not (web/'main.dart.js').is_file():p.error('Build compiled web first.')
    if out.exists() or archive.exists():p.error('Package destination already exists; use a new name.')
    out.mkdir(parents=True)
    for folder in ('app','migrations'):
        for source in (ROOT/'backend'/folder).rglob('*.py'):
            if '__pycache__' in source.parts:continue
            dest=out/'backend'/source.relative_to(ROOT/'backend');dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(source,dest)
    for name in ('alembic.ini','requirements.txt'):shutil.copy2(ROOT/'backend'/name,out/'backend'/name)
    shutil.copytree(web,out/'web',ignore=shutil.ignore_patterns('*.map','uat-phone.html'))
    for source in (ROOT/'scripts/demo').iterdir():
        if source.is_file():shutil.copy2(source,out/source.name)
    (out/'docs').mkdir()
    for source in (ROOT/'docs').glob('*.md'):shutil.copy2(source,out/'docs'/source.name)
    files={str(f.relative_to(out)).replace('\\','/'):hashlib.sha256(f.read_bytes()).hexdigest() for f in sorted(out.rglob('*')) if f.is_file()}
    (out/'manifest.json').write_text(json.dumps(dict(version='0.13.0',mode='isolated-synthetic-demo',files=files),indent=2),encoding='utf-8')
    with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED) as z:
        for f in out.rglob('*'):
            if f.is_file():z.write(f,str(f.relative_to(out)).replace('\\','/'))
    print(json.dumps(dict(archive=str(archive),bytes=archive.stat().st_size,sha256=hashlib.sha256(archive.read_bytes()).hexdigest(),files=len(files)+1)))

if __name__=='__main__':main()
