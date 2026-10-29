"""Explicit cloud settings and ingress trust; secrets never enter public config."""
from dataclasses import dataclass,field
from ipaddress import ip_address,ip_network
import os
from urllib.parse import urlsplit,parse_qs

@dataclass(frozen=True)
class Deployment:
    cloud:bool=False
    admin_password:str|None=field(default=None,repr=False)
    trusted_proxies:tuple=()
    cors_origins:tuple=('http://localhost:5173','http://127.0.0.1:5173')

    @classmethod
    def environment(cls):
        mode=os.getenv('APP_ENV','cloud' if os.getenv('RENDER')=='true' else 'local')
        if mode not in {'local','cloud'}:raise ValueError('APP_ENV must be local or cloud.')
        cloud=mode=='cloud';secret=os.getenv('ADMIN_PASSWORD')
        if cloud:
            if not secret or len(secret)<20 or secret=='DemoAssignment!2026':raise ValueError('Cloud requires a private ADMIN_PASSWORD of at least 20 characters.')
            url=os.getenv('DATABASE_URL','');u=urlsplit(url)
            if u.scheme not in {'postgresql','postgresql+psycopg'} or not u.hostname or not u.password:raise ValueError('Cloud requires an explicit PostgreSQL DATABASE_URL.')
            if parse_qs(u.query).get('sslmode',[''])[0] not in {'require','verify-ca','verify-full'}:raise ValueError('Cloud database must require TLS.')
        proxies=tuple(ip_network(x.strip()) for x in os.getenv('TRUSTED_PROXY_CIDRS','').split(',') if x.strip())
        if any(net.prefixlen==0 for net in proxies):raise ValueError('Do not trust all proxy addresses; configure specific ingress CIDRs.')
        origins=tuple(x.strip() for x in os.getenv('CORS_ORIGINS','' if cloud else 'http://localhost:5173,http://127.0.0.1:5173').split(',') if x.strip())
        if '*' in origins:raise ValueError('CORS_ORIGINS must contain explicit origins.')
        return cls(cloud,secret,proxies,origins)

    def peer(self,request):
        peer=request.client.host if request.client else 'unknown'
        def trusted(value):
            try:return any(ip_address(value) in net for net in self.trusted_proxies)
            except ValueError:return False
        if not trusted(peer):return peer
        chain=request.headers.get('x-forwarded-for','')
        if not chain or len(chain)>2048:return peer
        try:hops=[str(ip_address(x.strip())) for x in chain.split(',')]
        except ValueError:return peer
        # Remove only explicitly trusted right-hand hops. Never trust the first
        # client-supplied entry or enable Uvicorn's wildcard forwarding trust.
        for hop in reversed(hops):
            if not trusted(hop):return hop
        return peer
