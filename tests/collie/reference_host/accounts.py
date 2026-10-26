"""Private ChatGPT logins with explicit, durable account selection."""
import hashlib
import json
from pathlib import Path
import re
import uuid

from account import AUTH_CLAIM, account_details, claims, text
from linux_platform import atomic


def login_key(auth):
    if not isinstance(auth,dict) or auth.get('auth_mode')!='chatgpt':
        raise ValueError('Choose a ChatGPT Codex login')
    tokens=auth.get('tokens')
    if not isinstance(tokens,dict) or not text(tokens.get('account_id')) or not isinstance(tokens.get('access_token'),str) or not tokens['access_token']:
        raise ValueError('Login is missing an access token or account ID')
    if len(tokens['access_token'])>65536 or any(ord(c)<33 or ord(c)>126 for c in tokens['access_token']+tokens['account_id']):
        raise ValueError('Login contains invalid token or account ID fields')
    payload=claims(tokens['access_token']);identity=claims(tokens.get('id_token'));extra=payload.get(AUTH_CLAIM,{})
    if not isinstance(extra,dict):extra={}
    user=text(extra.get('chatgpt_user_id')) or text(payload.get('sub')) or text(identity.get('sub'))
    if not user:user=account_details(auth).get('email','').casefold()
    if not user:user=hashlib.sha256(tokens['access_token'].encode()).hexdigest()
    return hashlib.sha256((tokens['account_id']+'\0'+user).encode()).hexdigest()


class Accounts:
    def __init__(self,data):
        self.folder=Path(data)/'accounts';self.file=Path(data)/'accounts.json';self.cache={}
        try:saved=self.read(self.file)
        except FileNotFoundError:saved=dict(active='',entries=[])
        self.active=saved.get('active') if isinstance(saved,dict) else None
        self.entries=saved.get('entries') if isinstance(saved,dict) else None
        if not isinstance(self.active,str) or not isinstance(self.entries,list) or len(self.entries)>32:
            raise ValueError('Invalid saved account registry')
        ids=set();keys=set()
        for row in self.entries:
            if (not isinstance(row,dict) or not isinstance(row.get('id'),str) or not re.fullmatch('[a-f0-9]{32}',row['id'])
                    or row['id'] in ids or not isinstance(row.get('key'),str) or not re.fullmatch('[a-f0-9]{64}',row['key']) or row['key'] in keys
                    or ('source' in row and (not isinstance(row['source'],str) or not Path(row['source']).is_absolute()))):
                raise ValueError('Invalid saved account entry')
            ids.add(row['id']);keys.add(row['key'])
        if (self.entries and self.active not in ids) or (not self.entries and self.active):
            raise ValueError('The selected account is missing from the registry')

    @staticmethod
    def read(path):
        path=Path(path)
        if path.stat().st_size>1048576:raise ValueError('Login file exceeds 1 MiB')
        return json.loads(path.read_text())

    def get(self,id):
        for row in self.entries:
            if row['id']==id:return row
        raise ValueError('Saved account no longer exists')

    def path(self,id=None):
        return self.folder/(self.get(id or self.active)['id']+'.json')

    def save(self,entries,active):
        atomic(self.file,json.dumps(dict(active=active,entries=entries)).encode())
        self.entries=entries;self.active=active

    def add(self,auth,source=None,activate=False):
        encoded=json.dumps(auth).encode()
        if len(encoded)>1048576:raise ValueError('Login file exceeds 1 MiB')
        key=login_key(auth)
        row=next((dict(row) for row in self.entries if row['key']==key),None)
        if row is None:
            if len(self.entries)>=32:raise ValueError('Up to 32 accounts can be saved')
            row=dict(id=uuid.uuid4().hex,key=key)
        if source is not None:
            source=Path(source).resolve()
            if source.parent!=self.folder.resolve():row['source']=str(source)
        target=self.folder/(row['id']+'.json')
        self.folder.mkdir(mode=0o700,parents=True,exist_ok=True)
        if self.folder.is_symlink():raise ValueError('Account storage must be a private directory')
        self.folder.chmod(0o700)
        atomic(target,encoded)
        entries=[row if old['id']==row['id'] else old for old in self.entries]
        if not any(old['id']==row['id'] for old in self.entries):entries.append(row)
        active=row['id'] if activate or not self.active else self.active
        self.save(entries,active)
        return row

    def refresh(self,id=None):
        rows=[self.get(id)] if id else self.entries
        for row in rows:
            source=row.get('source')
            if not source:continue
            try:
                path=Path(source);stat=path.stat();stamp=(stat.st_dev,stat.st_ino,stat.st_size,stat.st_mtime_ns,stat.st_ctime_ns)
                cache_key=(row['id'],source)
                if self.cache.get(cache_key)==stamp:continue
                auth=self.read(path)
                # Codex may switch to another login in the original auth.json.
                # Only refresh matching credentials; never switch identities.
                if login_key(auth)==row['key']:
                    target=self.path(row['id'])
                    if not target.exists() or self.read(target)!=auth:atomic(target,json.dumps(auth).encode())
                self.cache[cache_key]=stamp
            except (OSError,ValueError,RecursionError):
                # The private copy remains usable when the source disappears.
                continue

    def auth(self,id=None):
        row=self.get(id or self.active);auth=self.read(self.path(row['id']))
        if login_key(auth)!=row['key']:raise ValueError('Saved login does not match this account; import it again')
        return auth

    def select(self,id):
        self.get(id);self.refresh(id);self.auth(id)
        self.save(self.entries,id)
        return self.path(id)

    def details(self):
        rows=[]
        for row in self.entries:
            try:details=account_details(self.auth(row['id']));available=True
            except (OSError,ValueError,RecursionError):details={};available=False
            rows.append(dict(details,id=row['id'],active=row['id']==self.active,available=available))
        return rows
