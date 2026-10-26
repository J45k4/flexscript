#!/usr/bin/env python3
"""Codex login protocol, lifecycle and native device-code UI with synthetic auth."""
import argparse
import asyncio
import base64
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from unittest.mock import AsyncMock, patch

from PIL import Image

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tests/collie/reference_host'))
from login import CodexLogin, browser_callback_available
from service import Desktop, Task


def auth(email,account):
    payload={'https://api.openai.com/profile':dict(name=email.split('@')[0],email=email),
             'https://api.openai.com/auth':dict(chatgpt_account_id=account,chatgpt_plan_type='plus')}
    token='header.'+base64.urlsafe_b64encode(json.dumps(payload).encode()).decode().rstrip('=')+'.signature'
    return dict(auth_mode='chatgpt',tokens=dict(access_token=token,account_id=account,refresh_token='synthetic-private'))


async def until(check):
    deadline=asyncio.get_running_loop().time()+12
    while not check():
        assert asyncio.get_running_loop().time()<deadline,'Login flow timed out'
        await asyncio.sleep(.02)


async def checks(out,work,passed):
    with patch('login.socket.socket',side_effect=OSError('busy')):
        try:browser_callback_available()
        except ValueError as error:assert 'use device code' in str(error)
        else:raise AssertionError('An occupied callback port was accepted')
    source=work/'first.json';source.write_text(json.dumps(auth('first@example.test','account-a')))
    other=work/'second.json';other.write_text(json.dumps(auth('second@example.test','account-b')))
    fixture=work/'fixture.json';fixture.write_text('[]');packets=[]
    d=Desktop(out/'engine',work/'data',auth=source,fixture=fixture,emit=packets.append)
    mode='complete';instances=[]
    def factory(home):
        client=CodexLogin(home,command=[sys.executable,str(ROOT/'tests/collie/login-server.py'),mode,str(other)])
        instances.append(client);return client
    try:
        await d.initialize();selected=d.accounts.active;original=source.read_bytes()
        d.open_login_browser=AsyncMock(return_value=True)
        with patch('service.CodexLogin',side_effect=factory),patch.dict(os.environ,{'OPENAI_API_KEY':'synthetic-environment-key'}):
            await d.command(dict(kind='start_account_login',method='browser'));await until(lambda:d.login_task is None)
            assert len(d.accounts.entries)==2 and d.accounts.active==selected and d.login_view['status']=='completed'
            assert d.open_login_browser.await_count==1 and source.read_bytes()==original
            assert json.loads((instances[-1].home/'environment.json').read_text())['api_key_present'] is False
            assert instances[-1].closed and instances[-1].process.returncode is not None
            passed('browser login starts asynchronously through Codex, isolates credentials/environment, saves the completed account and keeps the current selection')
            for mode in ('wait','late'):
                await d.command(dict(kind='start_account_login',method='device'));await until(lambda:d.login_view.get('code')=='TEST-CODE')
                assert d.login_view['url']=='https://auth.openai.com/codex/device'
                try:await d.command(dict(kind='select_account',id=selected))
                except ValueError as error:assert 'Finish or cancel' in str(error)
                else:raise AssertionError('Account selection raced sign-in')
                await d.command(dict(kind='cancel_account_login'))
                assert not instances[-1].home.exists() and instances[-1].process.returncode is not None
                assert len(d.accounts.entries)==2 and d.accounts.active==selected
            passed('device login exposes its verification code; cancellation kills the process, removes pending credentials and ignores late completion')
            mode='wait'
            await d.command(dict(kind='start_account_login',method='browser'));await until(lambda:d.login_view.get('url','').startswith('https://'))
            old=instances[-1]
            await d.command(dict(kind='start_account_login',method='device'));await until(lambda:d.login_view.get('code')=='TEST-CODE')
            assert old.closed and not old.home.exists() and d.login_view['method']=='device'
            await d.cancel_login()
            passed('switching login methods cancels and cleans the previous attempt before starting a replacement')
            mode='hang'
            await d.start_login('browser');await until(lambda:instances[-1].process is not None)
            await d.cancel_login()
            assert instances[-1].process.returncode is not None and not instances[-1].home.exists()
            for mode in ('failure','no-auth','invalid-url','start-error','exit'):
                await d.command(dict(kind='start_account_login',method='browser'));await until(lambda:d.login_task is None)
                assert d.login_view['status']=='error' and 'private synthetic error' not in json.dumps(d.login_view)
                assert len(d.accounts.entries)==2 and not instances[-1].home.exists()
            for id in (0,7):
                d.tasks[id]=Task(id)
                try:
                    try:await d.start_login('browser')
                    except ValueError as error:assert 'Stop active' in str(error)
                    else:raise AssertionError('Login started during an active task')
                finally:d.tasks.pop(id)
            passed('failed, refused, disconnected and malformed login attempts stay out of account storage; active replies and workers block starting sign-in')
            mode='wait'
            await d.start_login('device');await until(lambda:d.login_view.get('code')=='TEST-CODE')
            pending=instances[-1]
            await d.close();assert pending.closed and not pending.home.exists() and pending.process.returncode is not None
            passed('closing Collie cancels its pending login and leaves no running login process')
        assert 'synthetic-private' not in json.dumps(packets) and 'access_token' not in json.dumps(packets)
    finally:
        if not d.closed:await d.close()
    first=Desktop(out/'engine',work/'first-login-data',fixture=fixture,emit=lambda packet:None)
    try:
        await first.initialize();mode='complete'
        with patch('service.CodexLogin',side_effect=factory):
            await first.start_login('browser');await until(lambda:first.login_task is None)
        assert first.account()['email']=='second@example.test' and first.accounts.active
        assert first.login_view['message']=='Signed in. This account is now selected.'
        passed('first sign-in selects the new account automatically; adding subsequent accounts preserves the existing selection')
    finally:await first.close()
    return source,other,fixture


def capture(out,work,source,other,fixture,passed):
    wrapper=work/'login-service.py'
    wrapper.write_text('import argparse,asyncio,sys\nfrom pathlib import Path\n'
        +'sys.path.insert(0,'+repr(str(ROOT/'tests/collie/reference_host'))+')\nimport service\nfrom login import CodexLogin\n'
        +'service.CodexLogin=lambda home:CodexLogin(home,command='+repr([sys.executable,str(ROOT/'tests/collie/login-server.py'),'wait',str(other)])+')\n'
        +'p=argparse.ArgumentParser()\np.add_argument("--engine",type=Path,required=True)\np.add_argument("--data",type=Path)\np.add_argument("--auth",type=Path)\np.add_argument("--fixture",type=Path)\nasyncio.run(service.main(p.parse_args()))\n')
    events=work/'events.json';events.write_text(json.dumps([
        dict(at=100,request=dict(action='event',event=dict(key='desktop-settings',action='menu',action_id=0,type='click'))),
        dict(at=160,request=dict(action='event',event=dict(key='settings-nav-account',action='settings_section',action_id=2,type='click'))),
        dict(at=220,request=dict(action='event',event=dict(key='settings-account-device',action='start_account_login',action_id=1,type='click')))]))
    env=dict(os.environ,SDL_VIDEODRIVER='dummy',COLLIE_HEADLESS='1');env.pop('DISPLAY',None);env.pop('WAYLAND_DISPLAY',None)
    data=work/'native-data';state=work/'state.json';layout=work/'layout.json';raw=out/'desktop-account-device-login.rgba'
    result=subprocess.run([str(out/'collie-desktop'),'--service',str(wrapper),'--hidden','--frames','65','--data',str(data),'--auth',str(source),
        '--fixture',str(fixture),'--events',str(events),'--dump-state',str(state),'--dump-layout',str(layout),'--capture',str(raw)],env=env,capture_output=True,timeout=20)
    assert result.returncode==0,(result.returncode,result.stderr)
    facts=json.loads(state.read_text());boxes={r['key']:r for r in json.loads(layout.read_text())}
    assert facts['account_login']['code']=='TEST-CODE' and all(key in boxes for key in ('settings-signin-code','settings-signin-open','settings-signin-cancel'))
    assert len(facts['accounts'])==1 and not list((data/'account-logins').glob('*'))
    Image.frombytes('RGBA',(1280,860),raw.read_bytes()).save(out/'desktop-account-device-login.png')
    passed('native Add-account flow renders a device code, browser link and Cancel while keeping the existing account; closing the window cleans the login process')


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',type=Path,default=ROOT/'build/collie-desktop');out=p.parse_args().out.resolve();checks_run=[]
    def passed(text):checks_run.append(text);print('PASS',text,flush=True)
    with tempfile.TemporaryDirectory(prefix='login-',dir=out) as temp:
        work=Path(temp);source,other,fixture=asyncio.run(checks(out,work,passed));capture(out,work,source,other,fixture,passed)
    print(len(checks_run),'Codex login groups passed')


if __name__=='__main__':main()
