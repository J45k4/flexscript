"""Synthetic Codex stdio protocol peer; never contacts a login provider."""
import json
import os
from pathlib import Path
import sys

mode=sys.argv[1];auth=Path(sys.argv[2]);home=Path(os.environ['CODEX_HOME'])
(home/'environment.json').write_text(json.dumps(dict(isolated=True,api_key_present='OPENAI_API_KEY' in os.environ)))
def send(message):print(json.dumps(message),flush=True)
for line in sys.stdin:
    request=json.loads(line);method=request['method'];id=request.get('id')
    if method=='initialize':send(dict(id=id,result=dict(userAgent='synthetic')))
    elif method=='account/login/start':
        if mode=='hang':continue
        if mode=='start-error':
            send(dict(id=id,error=dict(code=-1,message='private synthetic error')));continue
        kind=request['params']['type']
        url='https://auth.openai.com/oauth/authorize?state=synthetic' if kind=='chatgpt' else 'https://auth.openai.com/codex/device'
        if mode=='invalid-url':url='https://unexpected.example/login'
        result=dict(type=kind,loginId='synthetic-login')
        if kind=='chatgpt':result['authUrl']=url
        else:result.update(verificationUrl=url,userCode='TEST-CODE')
        send(dict(id=id,result=result))
        if mode=='complete':
            (home/'auth.json').write_bytes(auth.read_bytes());(home/'auth.json').chmod(0o600)
            send(dict(method='account/login/completed',params=dict(loginId='another-attempt',success=False)))
            send(dict(method='account/login/completed',params=dict(loginId='synthetic-login',success=True)))
        elif mode in ('failure','no-auth'):
            send(dict(method='account/login/completed',params=dict(loginId='synthetic-login',success=mode=='no-auth',error='private synthetic error')))
        elif mode=='exit':break
    elif method=='account/login/cancel':
        send(dict(id=id,result=dict(status='canceled')))
        if mode=='late':
            (home/'auth.json').write_bytes(auth.read_bytes())
            send(dict(method='account/login/completed',params=dict(loginId='synthetic-login',success=True)))
