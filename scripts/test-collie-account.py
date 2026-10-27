#!/usr/bin/env python3
"""Current account display, bounded metadata and live auth-file refresh."""
import argparse
import asyncio
import base64
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from unittest.mock import patch

from PIL import Image

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tests/collie/reference_host'))
from account import AUTH_CLAIM, PROFILE_CLAIM, account_details
from accounts import Accounts
from service import Desktop, Task


def token(payload):
    return 'eyJhbGciOiJub25lIn0.'+base64.urlsafe_b64encode(json.dumps(payload).encode()).decode().rstrip('=')+'.synthetic'


def auth(name='Alex Example',email='alex@example.test',account='account-a',plan='plus'):
    return dict(auth_mode='chatgpt',tokens=dict(
        access_token=token({PROFILE_CLAIM:dict(name=name,email=email,picture='https://unused.example/avatar'),
                           AUTH_CLAIM:dict(chatgpt_account_id=account,chatgpt_plan_type=plan), 'unrelated':'private'}),
        id_token=token(dict(name='Older name',email='old@example.test')),
        account_id=account,refresh_token='synthetic-refresh-secret'))


def metadata(passed):
    original=auth();details=account_details(original)
    assert details==dict(name='Alex Example',email='alex@example.test',account_id='account-a',plan='Plus')
    assert 'synthetic-refresh-secret' not in json.dumps(details) and 'access_token' not in details
    fallback=dict(original,tokens=dict(original['tokens'],access_token='opaque'))
    assert account_details(fallback)['email']=='old@example.test'
    mismatch=dict(original,tokens=dict(original['tokens'],account_id='another-workspace'))
    assert 'plan' not in account_details(mismatch)
    for malformed in (None,[],{},dict(auth_mode='apikey'),dict(auth_mode='chatgpt',tokens=[])):
        assert account_details(malformed)=={}
    for malformed in ('bad','a.%%%.z','a.'+'x'*70000+'.z',token([]),token({PROFILE_CLAIM:[]})):
        result=account_details(dict(original,tokens=dict(original['tokens'],access_token=malformed,id_token='bad')))
        assert 'email' not in result and 'name' not in result
    assert account_details(auth(name='Alex\nExample',email='x'*300)).get('name')=='AlexExample'
    assert account_details(auth(email='x'*300))['email']=='old@example.test'
    passed('only bounded display metadata is exposed; malformed claims stay harmless and plans must match the selected account')


def storage(work,passed):
    shared=work/'shared-auth.json';shared.write_text(json.dumps(auth()))
    store=Accounts(work/'registry');a=store.add(auth(),shared)
    other=auth('Blair Example','blair@example.test','account-b','business')
    shared.write_text(json.dumps(other));b=store.add(other,shared)
    other['last_refresh']='B refreshed';shared.write_text(json.dumps(other));store.refresh()
    assert store.auth(a['id'])['tokens']['account_id']=='account-a' and store.auth(b['id'])['last_refresh']=='B refreshed'
    shared.unlink();store.select(b['id']);assert store.auth()['tokens']['account_id']=='account-b'
    store.path(a['id']).write_text(json.dumps(other))
    try:store.select(a['id'])
    except ValueError as error:assert 'does not match' in str(error)
    else:raise AssertionError('A saved account accepted another identity')
    assert store.active==b['id']
    invalid=auth();invalid['tokens']['access_token']='bad\nheader'
    try:store.add(invalid)
    except ValueError:pass
    else:raise AssertionError('Invalid authentication header was saved')
    assert store.active==b['id'] and len(store.entries)==2
    passed('multiple logins can follow the same Codex source without crossing identities; vanished sources and mismatched stored credentials cannot change selection')


async def flow(out,work,passed):
    packets=[];fixture=work/'fixture.json';fixture.write_text('[]');login=work/'auth.json';login.write_text(json.dumps(auth()))
    d=Desktop(out/'engine',work/'data',auth=login,fixture=fixture,emit=packets.append)
    try:
        await d.initialize()
        first=d.accounts.active
        assert next(p['data']['account'] for p in reversed(packets) if 'account' in p.get('data',{}))['email']=='alex@example.test'
        d.fixture=None
        current=d.read_auth();refreshed=json.loads(json.dumps(current));refreshed['last_refresh']='synthetic refresh'
        login.write_text(json.dumps(refreshed));await d.command(dict(kind='refresh_account'))
        assert d.read_auth()['last_refresh']=='synthetic refresh'
        login.write_text(json.dumps(auth('Blair Example','blair@example.test','account-b','business')))
        await d.command(dict(kind='refresh_account'))
        assert packets[-1]['data']['account']['email']=='alex@example.test'
        login.write_text('[]');await d.command(dict(kind='refresh_account'))
        assert packets[-1]['data']['account']['email']=='alex@example.test'
        imported=work/'imported.json';imported.write_text(json.dumps(auth('Blair Example','blair@example.test','account-b','business')))
        async def choose(title):return imported
        d.choose=choose
        await d.command(dict(kind='import_auth'))
        second=next(row['id'] for row in d.accounts.entries if row['id']!=first)
        assert len(d.accounts.entries)==2 and d.accounts.active==first and d.account()['email']=='alex@example.test'
        assert imported.read_text()==json.dumps(auth('Blair Example','blair@example.test','account-b','business'))
        await d.command(dict(kind='import_auth'));assert len(d.accounts.entries)==2 and d.accounts.active==first
        for id in (0,7):
            d.tasks[id]=Task(id)
            try:
                try:await d.command(dict(kind='select_account',id=second))
                except ValueError as error:assert 'Stop active replies and workers' in str(error)
                else:raise AssertionError('An active task allowed switching identities')
                assert d.accounts.active==first
            finally:d.tasks.pop(id)
        await d.command(dict(kind='select_account',id=second))
        assert packets[-1]['data']['account']['email']=='blair@example.test' and d.accounts.active==second
        assert sum(row['active'] for row in packets[-1]['data']['accounts'])==1
        class Response:
            def __enter__(self):return self
            def __exit__(self,*args):pass
            def __iter__(self):
                item=dict(type='message',role='assistant',content=[dict(type='output_text',text='Synthetic account reply')])
                yield ('data: '+json.dumps(dict(type='response.completed',response=dict(status='completed',output=[item])))+'\n').encode();yield b'\n'
        expected=d.read_auth()
        class Opener:
            def open(self,request,timeout):
                assert request.get_header('Authorization')=='Bearer '+expected['tokens']['access_token']
                assert request.get_header('Chatgpt-account-id')=='account-b'
                return Response()
        with patch('urllib.request.build_opener',return_value=Opener()):
            for id in (0,7):
                reply=await d.response(Task(id),{},0,False,[]);assert reply['message']=='Synthetic account reply'
        image_transport=await d.call(8,action='imagegen_transport',auth=d.read_auth())
        assert image_transport['headers']['ChatGPT-Account-ID']=='account-b'
        assert image_transport['headers']['Authorization']=='Bearer '+expected['tokens']['access_token']
        passed('adding keeps the current account, duplicate imports update it, active replies/workers block switching, and model/worker/image transports use the selected login')
        await d.command(dict(kind='select_account',id=first))
        d.navigation=dict(page='settings',settings_section='account',draft='Saved draft')
        d.save()
        saved=(d.root/'session.json').read_text()
        assert 'alex@example.test' not in saved and 'synthetic-refresh-secret' not in saved
        assert 'access_token' not in json.dumps(packets)
        d.account_metadata_enabled=False
        assert d.account()=={},'Fixtures without explicit auth must not expose the host identity'
        data=d.data;copied=d.auth_file
        assert all((d.accounts.path(row['id']).stat().st_mode&0o777)==0o600 for row in d.accounts.entries)
        assert d.accounts.folder.stat().st_mode&0o777==0o700
        passed('same-account refresh works without following another Codex identity; saved logins have private permissions and never enter conversation history')
    finally:await d.close()
    reopened=Desktop(out/'engine',data,emit=lambda packet:None)
    try:
        await reopened.initialize()
        assert reopened.accounts.active==first and reopened.account()['email']=='alex@example.test'
        await reopened.command(dict(kind='select_account',id=second))
        assert reopened.account()['email']=='blair@example.test'
        await reopened.command(dict(kind='select_account',id=first))
        selected_path=reopened.accounts.path();selected=selected_path.read_bytes();selected_path.unlink()
        # The original source is malformed, so a missing selected login cannot
        # silently route a request to another saved account.
        assert not reopened.authenticated() and reopened.accounts.active==first
        selected_path.write_bytes(selected);selected_path.chmod(0o600)
        passed('account selection survives restart and a missing selected login never falls back to another account')
    finally:await reopened.close()
    legacy=work/'legacy';legacy.mkdir();old=legacy/'auth.json';old.write_text(json.dumps(auth()))
    (legacy/'settings.json').write_text(json.dumps(dict(auth_file=str(old))))
    migrated=Desktop(out/'engine',legacy,emit=lambda packet:None)
    try:
        await migrated.initialize()
        assert migrated.account()['email']=='alex@example.test' and migrated.auth_file!=old
        assert json.loads(old.read_text())==auth() and 'auth_file' not in migrated.settings
        passed('an existing imported login migrates to private account storage without overwriting its original file')
    finally:await migrated.close()
    return data,copied,fixture


def capture(out,work,data,auth_file,fixture,passed):
    env=dict(os.environ,SDL_VIDEODRIVER='dummy',COLLIE_HEADLESS='1');env.pop('DISPLAY',None);env.pop('WAYLAND_DISPLAY',None)
    state=work/'state.json';layout=work/'layout.json';raw=out/'desktop-account-identity.rgba'
    result=subprocess.run([str(out/'collie'),'--hidden','--frames','45','--data',str(data),'--auth',str(auth_file),'--fixture',str(fixture),
        '--dump-state',str(state),'--dump-layout',str(layout),'--capture',str(raw)],env=env,capture_output=True,timeout=20)
    assert result.returncode==0,(result.returncode,result.stderr)
    facts=json.loads(state.read_text());boxes={row['key']:row for row in json.loads(layout.read_text())}
    assert facts['account']['email']=='alex@example.test' and facts['draft']=='Saved draft'
    assert len(facts['accounts'])==2
    assert all('settings-saved-'+row['id']+'-email' in boxes for row in facts['accounts'])
    other=next(row for row in facts['accounts'] if not row['active']);button=boxes['settings-account-use-'+other['id']]
    native=ROOT/'build/ui-desktop-events.so';events=work/'events.json';x=button['x']+button['width']//2;y=button['y']+button['height']//2
    events.write_text(json.dumps([dict(at=at,request=dict(action='native_mouse',fixture=str(native),kind=kind,a=1,b=x,c=y,d=0)) for at,kind in [(120,1025),(180,1026)]]))
    Image.frombytes('RGBA',(1280,860),raw.read_bytes()).save(out/'desktop-account-identity.png')
    result=subprocess.run([str(out/'collie'),'--hidden','--frames','45','--data',str(data),'--auth',str(auth_file),'--fixture',str(fixture),
        '--events',str(events),'--dump-state',str(state)],env=env,capture_output=True,timeout=20)
    assert result.returncode==0,(result.returncode,result.stderr)
    facts=json.loads(state.read_text());assert facts['account']['email']=='blair@example.test' and facts['draft']=='Saved draft'
    assert Accounts(data).active==other['id']
    passed('native Account settings show both logins and a real mouse click selects the other account without losing the draft')


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',type=Path,default=ROOT/'build/collie-desktop')
    out=p.parse_args().out.resolve();checks=[]
    def passed(text):checks.append(text);print('PASS',text,flush=True)
    metadata(passed)
    with tempfile.TemporaryDirectory(prefix='account-',dir=out) as temp:
        work=Path(temp);storage(work,passed);data,login,fixture=asyncio.run(flow(out,work,passed));capture(out,work,data,login,fixture,passed)
    print(len(checks),'account identity groups passed')


if __name__=='__main__':main()
