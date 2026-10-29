"""Single Render process: same-origin web/API, external TLS PostgreSQL only."""
import os
import uvicorn

if __name__=='__main__':
    port=int(os.getenv('PORT','10000'))
    if not 1<=port<=65535:raise ValueError('Invalid PORT.')
    # Forwarding is resolved by our explicit CIDR policy, never wildcard trust.
    uvicorn.run('app.main:app',host='0.0.0.0',port=port,workers=1,proxy_headers=False)
