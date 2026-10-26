"""Managed browser/device login through the installed Codex app-server protocol."""
import asyncio
import contextlib
import json
import os
from pathlib import Path
import shutil
import signal
import socket
from urllib.parse import urlsplit


def login_url(value):
    if not isinstance(value,str) or len(value)>16384 or any(ord(c)<33 for c in value):
        raise ValueError('Codex returned an invalid sign-in URL')
    parsed=urlsplit(value)
    if parsed.scheme!='https' or parsed.hostname not in ('auth.openai.com','chatgpt.com') or parsed.username or parsed.password or parsed.port not in (None,443):
        raise ValueError('Codex returned an unexpected sign-in destination')
    return value


def browser_callback_available():
    # Codex 0.164 tries /cancel on an occupied callback port. Check before
    # starting browser auth so Collie cannot cancel somebody else's CLI login.
    try:
        with socket.socket(socket.AF_INET,socket.SOCK_STREAM) as probe:probe.bind(('127.0.0.1',1455))
    except OSError:
        raise ValueError('Browser callback port is unavailable. Finish the other login or use device code.') from None


class CodexLogin:
    def __init__(self,home,command=None):
        executable=shutil.which('codex')
        if command is None and not executable:
            raise ValueError('Install Codex CLI to sign in, or import an existing login')
        self.command=command or [executable,'-c','cli_auth_credentials_store="file"','-c','forced_login_method="chatgpt"','app-server','--stdio']
        self.managed_command=command is None
        self.home=Path(home);self.process=None;self.reader=None;self.pending={};self.notifications=asyncio.Queue(maxsize=64)
        self.sequence=0;self.login_id=None;self.url='';self.code='';self.closed=False

    async def send(self,message):
        self.process.stdin.write(json.dumps(message,separators=(',',':')).encode()+b'\n')
        await asyncio.wait_for(self.process.stdin.drain(),5)

    async def request(self,method,params,timeout=45):
        self.sequence+=1;id=self.sequence;future=asyncio.get_running_loop().create_future();self.pending[id]=future
        try:
            await self.send(dict(id=id,method=method,params=params))
            return await asyncio.wait_for(future,timeout)
        finally:
            self.pending.pop(id,None)
            if not future.done():future.cancel()
            elif not future.cancelled():future.exception()

    async def read(self):
        try:
            while True:
                line=await self.process.stdout.readline()
                if not line:raise ValueError('Codex sign-in process exited before completion')
                message=json.loads(line)
                if not isinstance(message,dict):raise ValueError('Invalid Codex login response')
                if 'id' in message and ('result' in message or 'error' in message):
                    future=self.pending.get(message['id'])
                    if future and not future.done():
                        if 'error' in message:future.set_exception(ValueError('Codex could not start this sign-in method. Try device code or check Codex login requirements.'))
                        else:future.set_result(message['result'])
                elif message.get('method')=='account/login/completed':
                    self.notifications.put_nowait(message.get('params',{}))
                elif 'id' in message:
                    await self.send(dict(id=message['id'],error=dict(code=-32601,message='Unsupported login client request')))
        except asyncio.CancelledError:raise
        except Exception:
            error=ValueError('Codex sign-in connection closed or returned an invalid response')
            for future in self.pending.values():
                if not future.done():future.set_exception(error)
            with contextlib.suppress(asyncio.QueueFull):self.notifications.put_nowait(dict(disconnected=True))

    async def start(self,method='browser'):
        if method not in ('browser','device'):raise ValueError('Unknown sign-in method')
        self.home.mkdir(mode=0o700,parents=True,exist_ok=False)
        env=dict(os.environ,CODEX_HOME=str(self.home))
        for key in ('OPENAI_API_KEY','CODEX_API_KEY','CODEX_ACCESS_TOKEN','CODEX_APP_SERVER_LOGIN_ISSUER','CODEX_APP_SERVER_LOGIN_OPEN_APP_URL'):
            env.pop(key,None)
        spawn=asyncio.create_task(asyncio.create_subprocess_exec(*self.command,env=env,cwd=self.home,
            stdin=asyncio.subprocess.PIPE,stdout=asyncio.subprocess.PIPE,stderr=asyncio.subprocess.DEVNULL,
            limit=1048576,start_new_session=True))
        try:self.process=await asyncio.shield(spawn)
        except asyncio.CancelledError:
            self.process=await spawn
            raise
        self.reader=asyncio.create_task(self.read())
        await self.request('initialize',dict(clientInfo=dict(name='collie',title='Collie',version='0.1.0'),capabilities={}))
        await self.send(dict(method='initialized',params={}))
        if method=='browser' and self.managed_command:browser_callback_available()
        kind='chatgpt' if method=='browser' else 'chatgptDeviceCode'
        result=await self.request('account/login/start',dict(type=kind),timeout=60)
        if not isinstance(result,dict) or result.get('type')!=kind or not isinstance(result.get('loginId'),str) or not 1<=len(result['loginId'])<=128:
            raise ValueError('Codex did not return a managed sign-in attempt')
        self.login_id=result['loginId']
        self.url=login_url(result.get('authUrl') if method=='browser' else result.get('verificationUrl'))
        if method=='device':
            code=result.get('userCode')
            if not isinstance(code,str) or not 1<=len(code)<=64 or any(ord(c)<33 or ord(c)>126 for c in code):
                raise ValueError('Codex returned an invalid device code')
            self.code=code
        return dict(method=method,url=self.url,code=self.code)

    async def wait(self):
        async with asyncio.timeout(16*60):
            while True:
                message=await self.notifications.get()
                if message.get('disconnected'):raise ValueError('Codex sign-in connection closed')
                if message.get('loginId')!=self.login_id:continue
                if message.get('success') is not True:
                    raise ValueError('Sign-in was not completed. Try again or choose device code.')
                path=self.home/'auth.json'
                if not path.is_file():raise ValueError('Codex completed sign-in without saving a login')
                return path

    async def close(self):
        if self.closed:return
        self.closed=True
        process=self.process
        if process is not None:
            if process.returncode is None and self.login_id:
                with contextlib.suppress(Exception):await self.request('account/login/cancel',dict(loginId=self.login_id),timeout=2)
            if process.returncode is None:
                process.stdin.close()
                with contextlib.suppress(ProcessLookupError):os.killpg(process.pid,signal.SIGTERM)
                try:await asyncio.wait_for(process.wait(),3)
                except asyncio.TimeoutError:
                    with contextlib.suppress(ProcessLookupError):os.killpg(process.pid,signal.SIGKILL)
                    await process.wait()
        if self.reader:
            self.reader.cancel();await asyncio.gather(self.reader,return_exceptions=True)
