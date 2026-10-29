"""Single Render process: same-origin web/API, external TLS PostgreSQL only."""
import os
import sys
from pathlib import Path
import uvicorn

if __name__=='__main__':
    backend=Path(__file__).resolve().parent/'backend'
    if not (backend/'app/main.py').is_file():backend=Path(__file__).resolve().parents[1]/'backend'
    if not (backend/'app/main.py').is_file():raise RuntimeError('Backend application directory was not found.')
    sys.path.insert(0,str(backend))
    port=int(os.getenv('PORT','10000'))
    if not 1<=port<=65535:raise ValueError('Invalid PORT.')
    # Forwarding is resolved by our explicit CIDR policy, never wildcard trust.
    uvicorn.run('app.main:app',host='0.0.0.0',port=port,workers=1,proxy_headers=False)
