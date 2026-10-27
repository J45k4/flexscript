#!/usr/bin/env python3
"""Headless desktop app flows, real native VM checkpoints and rendered SDL UI."""
import argparse
import asyncio
import io
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import time
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tests/collie/reference_host'))
from service import Desktop, Task
from linux_platform import atomic
from linux_platform import Platform, Failure
from PIL import Image


def completed(*items):
    return {'type': 'response.completed', 'response': {'status': 'completed', 'output': list(items), 'usage': {'input_tokens': 20, 'output_tokens': 10, 'total_tokens': 30}}}


def message(text):
    return {'type': 'message', 'role': 'assistant', 'content': [{'type': 'output_text', 'text': text}]}


def tool(source, key='desktop'):
    return {'type': 'custom_tool_call', 'id': 'ctc_'+key, 'call_id': 'call_'+key, 'name': 'flexscript', 'input': source, 'status': 'completed'}


async def until(predicate, seconds=8):
    end = asyncio.get_running_loop().time()+seconds
    while not predicate():
        if asyncio.get_running_loop().time() >= end:
            raise AssertionError('Timed out waiting for desktop task')
        await asyncio.sleep(0.02)


async def integration(out, work, passed):
    fixture = work/'fixture.json'
    source = 'fn main(){let x=alloc(8);store64(x,42);if(!fs_write("desktop.txt",db_text("Desktop persisted"))){return 7;}progress("Saved a real file");let answer=agent_ask("Check the result");if(!answer){return 8;}db_io(0,1,db_word(answer),db_bytes(answer));return load64(x)-42;}'
    fixture.write_text(json.dumps([completed(tool(source)), completed(message('Feedback verified')), completed(message('Desktop completed'))]))
    packets = []
    d = Desktop(out/'engine', work/'data', fixture=fixture, emit=packets.append)
    try:
        await d.initialize()
        assert d.permissions['approval_reviewer']=='user' and {v for k,v in d.permissions.items() if k not in ('approval_reviewer','permission_profile')} == {'ask'}
        assert len(d.permission_entries)==11 and all(row['key'] not in ('nfc','bluetooth','uwb','camera') for row in d.permission_entries)
        assert not d.tasks
        before=len(packets)
        await asyncio.sleep(0.65)
        assert len(packets)==before,'Idle desktop must not poll the engine or emit worker updates'
        passed('opening desktop starts no model request and uses the shared 31 first-use grants')
        await d.command({'kind': 'submit', 'text': 'Desktop end to end'})
        await until(lambda: d.prompts)
        assert d.prompts[0][1]['key'] == 'files_write'
        assert not (d.root/'files/desktop.txt').exists()
        await d.command(dict(kind='permission_decision', request_id=d.prompts[0][1]['request_id'], allowed=True, stop=False))
        await until(lambda: d.prompts and d.prompts[0][1]['key'] == 'workers')
        assert (d.root/'files/desktop.txt').read_text() == 'Desktop persisted'
        await d.command(dict(kind='permission_decision', request_id=d.prompts[0][1]['request_id'], allowed=True, stop=False))
        await until(lambda: not d.tasks)
        kinds = [card['kind'] for card in d.state['cards']]
        assert 'progress' in kinds and 'feedback' in kinds and 'result' in kinds
        result = next(card['observation'] for card in d.state['cards'] if card['kind'] == 'result')
        assert result['stdout'] == 'Feedback verified' and result['exit_code'] == 0
        assert d.state['messages'][-1]['role'] == 'assistant'
        passed('submit, lazy approvals, file effects, progress, model feedback and original VM locals complete through the actual desktop controller')
        first = d.root.name
        await d.command(dict(kind='permission', key='history', allowed=True))
        await d.command({'kind': 'load_sessions'})
        sessions = next(p['data']['sessions'] for p in reversed(packets) if 'sessions' in p.get('data', {}))
        assert sessions[0]['id'] == first and sessions[0]['title'] == 'Desktop end to end'
        await d.command({'kind': 'new_session'})
        second = d.root.name
        assert first != second and not d.state['cards']
        await d.command(dict(kind='open_session', id=first))
        assert any(card.get('text') == 'Desktop completed' for card in d.state['cards'])
        assert d.permissions['history'] is True
        passed('shared conversation summaries, new/open navigation and permissions persist across distinct workspaces')
        await d.command(dict(kind='open_session', id=second))
        await d.command(dict(kind='permission', key='history', allowed=True))
        r = await d.call(3, source='fn main(){let p=memory_search("Desktop end to end","",0,20);if(!p){return 9;}return db_count(db_at(p,0));}', call_id='recall')
        assert r['exit_code'] > 0 and not r['stderr'], r
        passed('desktop recall reads the real prior session archive through the shared permission-filtered broker')
        image_path = work/'photo.png'
        image = Image.new('RGB', (1800, 900), '#abc123'); image.save(image_path)
        await d.attach(image_path)
        attachment = d.attachments[0]
        assert attachment['type'] == 'image' and attachment['width'] == 1536
        assert (d.root/'images'/f"{attachment['image_id']}.jpg").is_file()
        await d.command(dict(kind='remove_attachment', index=0))
        text_path = work/'unicode.txt'; text_path.write_text('中文 café\nDesktop attachment')
        await d.attach(text_path)
        assert d.attachments[0]['text'].startswith('中文')
        await d.command(dict(kind='remove_attachment', index=0))
        passed('real file and image attachments create bounded private snapshots, preserve Unicode and can be removed')
        d.fixture = {'main': [completed(tool('fn main(){let id=worker_start("Counter","Calculate 6 times 7");let x=alloc(8);store64(x,77);let row=worker_await(id);let v=worker_result(row);db_io(0,1,db_word(v),db_bytes(v));return load64(x)-77;}', 'delegate')), completed(message('Worker finished'))],
                     'workers': {'1': [completed(message('42'))]}}
        await d.command(dict(kind='permission', key='workers', allowed=True))
        await d.command(dict(kind='submit', text='Delegate'))
        await until(lambda: not d.tasks, 12)
        results = [c['observation'] for c in d.state['cards'] if c['kind'] == 'result']
        assert results[-1]['stdout'] == '42' and results[-1]['exit_code'] == 0, d.state
        await d.command(dict(kind='load_worker', id=1))
        rows = next(p['data']['worker_messages'] for p in reversed(packets) if 'worker_messages' in p.get('data', {}))
        assert any('42' in str(row) for row in rows)
        passed('desktop scheduler launches the shared worker machine and resumes the parent VM heap from its durable checkpoint')
        owner=d.root.name
        pending_events=[{'type':'response.output_text.delta','delta':'Working'}]+[{'type':'response.created'}]*200+[completed(message('Working'))]
        d.fixture={'main':[completed(tool('fn main(){return worker_start("Background","Wait")-2;}','background')),completed(message('Background worker started'))],
                   'workers':{'2':[{'events':pending_events}]}}
        await d.command(dict(kind='submit',text='Background work'))
        await until(lambda: 0 not in d.tasks and 2 in d.tasks)
        await d.command(dict(kind='new_session'))
        assert not d.tasks and d.root.name!=owner
        await d.command(dict(kind='open_session',id=owner))
        rows=(await d.call(9,action='list'))['workers']
        assert rows[1][1][2]=='paused',rows
        d.fixture['workers']['2']=[completed(message('Resumed worker'))]
        await d.command(dict(kind='worker_action',action='resume',id=2))
        await until(lambda: not d.tasks)
        assert (await d.call(9,action='list'))['workers'][1][1][2]=='done'
        passed('switching conversations pauses background workers; reopening and Resume use the shared durable worker journal')
        # The actual service bridge returns typed Linux hardware values and
        # explicit unsupported results. No external network/device mutation.
        await d.command(dict(kind='permission', key='device_status', allowed=True))
        r = await d.call(3, source='fn main(){let v=battery_info();if(!v){return 9;}return db_kind(v)-5;}', call_id='battery')
        assert r['exit_code'] == 0, r
        r = await d.call(3, source='fn main(){let v=hardware_access_info();if(!v){return 9;}let p=device_field(v,"platform");db_io(0,1,db_word(p),db_bytes(p));return 0;}', call_id='facts')
        assert r['stdout'] == 'linux', r
        passed('native guest hardware RPC reaches the actual Linux platform service and returns real OS facts')
        # Exercise the actual desktop HTTPS/SSE transport adapter with an
        # in-memory response, synthetic credentials and no outbound request.
        auth_file=work/'synthetic-auth.json'
        auth_file.write_text(json.dumps({'auth_mode':'chatgpt','tokens':{'access_token':'synthetic','account_id':'test-account'}}))
        d.auth_file=auth_file
        fixture_saved=d.fixture;d.fixture=None
        live_task=Task(0);d.tasks[0]=live_task
        class Response:
            def __enter__(self):return self
            def __exit__(self,*args):pass
            def __iter__(self):
                for event in [{'type':'response.output_text.delta','delta':'Streamed desktop'},completed(message('Streamed desktop'))]:
                    yield ('data: '+json.dumps(event)+'\n').encode();yield b'\n'
        class Opener:
            def open(self,request,timeout):
                assert request.full_url=='https://chatgpt.com/backend-api/codex/responses'
                assert request.get_header('Authorization')=='Bearer synthetic' and timeout==30
                return Response()
        try:
            with patch('urllib.request.build_opener',return_value=Opener()):
                reply=await d.response(live_task,{},0,False,[])
            assert reply['message']=='Streamed desktop'
            assert any(p.get('data',{}).get('stream')=='Streamed desktop' for p in packets)
        finally:
            d.tasks.pop(0,None);d.fixture=fixture_saved
        passed('desktop HTTPS adapter sends only the shared provider request and validates streamed SSE through the real native provider')
        archive_size=len(d.state['archive'])
        d.fixture=[None]*d.state.get('requests',0)+[completed({'type':'compaction','encrypted_content':'desktop-opaque-checkpoint'})]
        await d.command(dict(kind='compact'))
        await until(lambda: not d.tasks)
        assert d.state['messages'][-1]['encrypted_content']=='desktop-opaque-checkpoint'
        assert len(d.state['archive'])==archive_size
        passed('desktop manual compaction replaces active context while retaining real archived history')
        d.fixture = [completed(tool('fn main(){while 1{}return 0;}', 'cancel'))]
        await d.command(dict(kind='submit', text='Cancellable program'))
        await until(lambda: any(p.get('data', {}).get('status') == 'Running Flexscript…' for p in packets[-20:]))
        await d.command(dict(kind='cancel'))
        await until(lambda: not d.tasks)
        assert not d.state.get('pending_execution')
        passed('Stop cancels the live task and records a paired failure without leaving an automatically replayable program')
        await d.command(dict(kind='permission',key='files_write',allowed='ask'))
        d.fixture=[completed(tool('fn main(){return fs_write("must-not-exist",db_text("not written"));}','stop-at-prompt'))]
        await d.command(dict(kind='submit',text='Cancel at first use'))
        await until(lambda:d.prompts)
        await d.command(dict(kind='permission_decision',request_id=d.prompts[0][1]['request_id'],allowed=False,stop=True))
        await until(lambda:not d.tasks)
        assert d.permissions['files_write']=='ask' and not (d.root/'files/must-not-exist').exists()
        passed('Stop at a lazy approval cancels without executing the operation or changing the saved Ask choice')
        # Restart reloads full session state, without sending another request.
        saved_root = d.root.name
        saved_cards = len(d.state['cards'])
        await d.close()
        d = Desktop(out/'engine', work/'data', fixture=fixture, emit=packets.append)
        await d.initialize()
        assert d.root.name == saved_root and len(d.state['cards']) == saved_cards and not d.tasks
        passed('application restart restores the saved conversation and never starts a model turn automatically')
    finally:
        await d.close()


async def message_links(out, work, passed):
    fixture=work/'links-fixture.json';fixture.write_text('[]')
    d=Desktop(out/'engine',work/'link-data',fixture=fixture,emit=lambda packet:None)
    try:
        await d.initialize()
        path=d.root/'files'/'tetris.html';path.write_text('<!doctype html><title>Tetris fixture</title>')
        with patch('service.webbrowser.open',return_value=True) as browser, patch.dict(os.environ,{'COLLIE_HEADLESS':'0'}):
            assert not browser.called
            await d.command(dict(kind='open_link',href='tetris.html'))
            browser.assert_called_once_with(path.as_uri(),new=2)
            await d.command(dict(kind='open_link',href='https://example.com/guide_(desktop)?q=42#play'))
            assert browser.call_args.args[0]=='https://example.com/guide_(desktop)?q=42#play'
            (d.root/'files'/'outside').symlink_to(work)
            for href in ('javascript:alert(1)','file:///etc/passwd','../session.json','%2e%2e/session.json','missing.html','outside/links-fixture.json'):
                before=browser.call_count
                try: await d.command(dict(kind='open_link',href=href))
                except ValueError: pass
                else: raise AssertionError('Unexpected link acceptance: '+href)
                assert browser.call_count==before
            with patch.dict(os.environ,{'COLLIE_HEADLESS':'1'}):
                before=browser.call_count
                try: await d.command(dict(kind='open_link',href='tetris.html'))
                except ValueError as error: assert 'headless' in str(error)
                else: raise AssertionError('Headless check attempted a browser launch')
                assert browser.call_count==before
        passed('clicked workspace/web links resolve to the right browser target; missing files, escapes, other schemes and headless launches are rejected')
    finally:
        await d.close()


async def thinking_stream(out, work, passed):
    summary = 'Checking the inputs before calculating the result.'
    item = dict(type='reasoning', id='rs_desktop', encrypted_content='private-reasoning-fixture',
                summary=[dict(type='summary_text', text=summary)])
    fixture = work/'thinking-fixture.json'
    fixture.write_text(json.dumps([dict(events=[
        *[dict(type='response.in_progress') for _ in range(8)],
        dict(type='response.reasoning_summary_text.delta',item_id='rs_desktop',summary_index=0,delta=summary),
        *[dict(type='response.in_progress') for _ in range(12)],
        completed(item, message('The answer is 42.'))])]))
    packets = []
    data = work/'thinking-data'
    d = Desktop(out/'engine',data,fixture=fixture,emit=packets.append)
    try:
        await d.initialize()
        await d.command(dict(kind='submit',text='Calculate the answer'))
        await until(lambda:any(p.get('data',{}).get('live',{}).get('summaries')==[] for p in packets))
        assert any(p.get('data',{}).get('busy') is True for p in packets) and d.tasks
        def live_summary():
            return any(p.get('data',{}).get('live',{}).get('summaries') for p in packets)
        await until(live_summary)
        live = next(p['data']['live'] for p in packets if p.get('data',{}).get('live',{}).get('summaries'))
        assert live['summaries'][0]['text']==summary and not live['text'] and d.tasks
        assert 'private-reasoning-fixture' not in json.dumps(packets)
        await until(lambda: not d.tasks)
        assert [c['text'] for c in d.state['cards'] if c['kind']=='thinking']==[summary]
        assert d.state['cards'][-1]['text']=='The answer is 42.'
        await d.close()
        d = Desktop(out/'engine',data,fixture=fixture,emit=packets.append)
        await d.initialize()
        assert [c['text'] for c in d.state['cards'] if c['kind']=='thinking']==[summary]
        passed('desktop controller streams public thinking summaries before completion and restores their saved cards separately from replies')
    finally:
        await d.close()


async def session_order(out, work, passed):
    data = work/'session-order'
    sessions = data/'sessions'
    expected = ['newest', 'middle', 'oldest']
    for index, id in enumerate(reversed(expected)):
        path = sessions/id
        path.mkdir(parents=True)
        messages = [dict(role='user', content=id), dict(role='assistant', content='Saved reply')]
        saved = dict(messages=messages, archive=messages, cards=[dict(kind='user', text=id), dict(kind='assistant', text='Saved reply')])
        (path/'session.json').write_text(json.dumps(saved))
        os.utime(path/'session.json', (1700000000+index, 1700000000+index))
    (data/'settings.json').write_text(json.dumps(dict(current='oldest')))
    fixture = work/'order-fixture.json'
    fixture.write_text(json.dumps([completed(message('A new reply'))]))
    def ids(d):return [row['id'] for row in d.session_entries]
    d = Desktop(out/'engine', data, fixture=fixture, emit=lambda packet: None)
    try:
        await d.initialize()
        assert ids(d)==expected, ids(d)
        original_activity = d.last_activity
        assert original_activity==1700000000000
        await d.command(dict(kind='navigation', data=dict(page='chat', draft='An unsent draft')))
        await d.command(dict(kind='permission', key='files_read', allowed=True))
        await d.command(dict(kind='save_model', model='gpt-6.1-sol'))
        await d.command(dict(kind='load_sessions'))
        assert ids(d)==expected and d.last_activity==original_activity
        await d.command(dict(kind='open_session', id='middle'))
        await asyncio.sleep(0.65)
        await d.command(dict(kind='load_sessions'))
        assert ids(d)==expected, ids(d)
        await d.close()
        d = Desktop(out/'engine', data, fixture=fixture, emit=lambda packet: None)
        await d.initialize()
        assert d.root.name=='middle' and ids(d)==expected
        await d.command(dict(kind='open_session', id='oldest'))
        assert d.last_activity==original_activity and ids(d)==expected
        passed('opening, reading, drafts, settings and restart preserve conversation order and migrate legacy timestamps')
        await d.command(dict(kind='submit', text='An actual new message'))
        await until(lambda: not d.tasks)
        assert d.state['cards'][-1]['text']=='A new reply'
        assert ids(d)==['oldest', 'newest', 'middle'], ids(d)
        assert d.last_activity>original_activity
        saved_activity = d.last_activity
        await d.command(dict(kind='load_sessions'))
        assert ids(d)==['oldest', 'newest', 'middle']
        await d.close()
        d = Desktop(out/'engine', data, fixture=fixture, emit=lambda packet: None)
        await d.initialize()
        assert ids(d)==['oldest', 'newest', 'middle'] and d.last_activity==saved_activity
        passed('a real submitted message promotes the conversation and persists its activity order across reload and restart')
    finally:
        await d.close()


async def session_cache(out, work, passed):
    data = work/'session-cache'
    for id in ('first', 'second', 'third'):
        path = data/'sessions'/id
        path.mkdir(parents=True)
        (path/'session.json').write_text(json.dumps(dict(messages=[dict(role='user', content=id)], cards=[])))
    (data/'settings.json').write_text(json.dumps(dict(current='first')))
    fixture = work/'cache-fixture.json';fixture.write_text('[]')
    d = Desktop(out/'engine', data, fixture=fixture, emit=lambda packet: None)
    try:
        await d.initialize()
        with patch.object(d, 'call', wraps=d.call) as calls:
            await d.load_sessions()
            assert not calls.call_args_list, 'Unchanged summaries must not restart ui-host'
            await d.command(dict(kind='open_session', id='second'))
            assert sum(c.args[0]==11 for c in calls.call_args_list)==1
        path = data/'sessions'/'third'/'session.json'
        saved = json.loads(path.read_text());saved['messages'][0]['content']='Changed title'
        atomic(path, json.dumps(saved).encode())
        with patch.object(d, 'call', wraps=d.call) as calls:
            await d.load_sessions()
            assert len(calls.call_args_list)==1 and calls.call_args.args[0]==11
            assert next(r for r in d.session_entries if r['id']=='third')['title']=='Changed title'
            path.unlink();await d.load_sessions()
            assert len(calls.call_args_list)==1 and 'third' not in [r['id'] for r in d.session_entries]
            assert path not in d.session_summaries
        passed('chat switching reuses unchanged sidebar summaries and refreshes replaced or removed conversations')
        with patch('service.atomic', wraps=atomic) as writes:
            d.save();d.save()
            assert not writes.called
            await d.command(dict(kind='navigation', data=dict(page='chat', draft='Persist this draft')))
            assert writes.call_count==1 and writes.call_args.args[0]==d.root/'session.json'
            d.save();assert writes.call_count==1
        # A failed write must never populate the successful-write cache. A
        # partial save retries only the settings file that has not reached disk.
        d.model='gpt-6-astra'
        def fail_settings(path, encoded):
            if path==data/'settings.json':raise OSError('Synthetic storage failure')
            atomic(path, encoded)
        with patch('service.atomic', side_effect=fail_settings):
            try:d.save()
            except OSError:pass
            else:raise AssertionError('Storage errors must propagate')
        with patch('service.atomic', wraps=atomic) as writes:
            d.save()
            assert writes.call_count==1 and writes.call_args.args[0]==data/'settings.json'
        await d.close()
        d = Desktop(out/'engine', data, fixture=fixture, emit=lambda packet: None)
        await d.initialize()
        assert d.root.name=='second' and d.navigation['draft']=='Persist this draft' and d.model=='gpt-6-astra'
        passed('unchanged saves avoid disk flushes while changed drafts, settings, failed-write retries and restart remain durable')
    finally:
        await d.close()


def native_ui(out, work, passed):
    fixture = work/'ui-fixture.json'
    fixture.write_text(json.dumps([completed(tool('fn main(){let text="42\\n";db_io(0,1,text,3);return 0;}')), completed(message('The result is **42**.'))]))
    events = work/'events.json'
    def event(at, key, action, value=None, type='click', id=0):
        return {'at': at, 'request': {'action': 'event', 'event': {'key': key, 'action': action, 'action_id': id, 'type': type, 'value': value}}}
    events.write_text(json.dumps([event(150,'composer-draft','draft','Calculate 6 × 7', 'change'),event(170,'composer-send','send')]))
    env = dict(os.environ, SDL_VIDEODRIVER='dummy', COLLIE_HEADLESS='1')
    env.pop('DISPLAY', None); env.pop('WAYLAND_DISPLAY', None)
    command = [str(out/'collie'),'--width','1000','--height','800','--hidden','--frames','120','--data',str(work/'native-ui'), '--fixture',str(fixture),
               '--events',str(events),'--capture',str(out/'desktop-chat.rgba'),'--dump-state',str(work/'ui-state.json')]
    result = subprocess.run(command, env=env, capture_output=True, timeout=15)
    assert result.returncode == 0, (result.returncode, result.stderr)
    state = json.loads((work/'ui-state.json').read_text())
    assert state['cards'][-1]['text'] == 'The result is **42**.', state
    assert any(c['kind']=='result' and c['observation']['stdout']=='42\n' for c in state['cards']), state
    raw = (out/'desktop-chat.rgba').read_bytes()
    assert len(raw) == 1000*800*4 and len(set(raw[::4])) > 50
    Image.frombytes('RGBA',(1000,800),raw).save(out/'desktop-chat.png')
    passed('native SDL shell routes real shared composer events to the checked VM and renders the returned transcript to pixels')
    # Repeated permission renders verify model scratch does not retain freed
    # entry pointers. The same app screens are captured at desktop dimensions.
    events.write_text(json.dumps([event(100,'desktop-settings','menu'),event(140,'settings-nav-access','settings_section',id=1),
                                  event(180,'allow-files_read','files_read'),event(220,'deny-files_read','files_read')]))
    result = subprocess.run([str(out/'collie'),'--width','1000','--height','800','--hidden','--frames','60','--data',str(work/'native-ui'),'--fixture',str(fixture),
                             '--events',str(events),'--capture',str(out/'desktop-permissions.rgba'),'--dump-state',str(work/'ui-state.json')], env=env, capture_output=True, timeout=15)
    assert result.returncode == 0, (result.returncode, result.stderr)
    state = json.loads((work/'ui-state.json').read_text())
    assert state['page'] == 'settings' and state['settings_section']=='access' and state['policy']['files_read'] is False, state
    Image.frombytes('RGBA',(1000,800),(out/'desktop-permissions.rgba').read_bytes()).save(out/'desktop-permissions.png')
    passed('the actual desktop permissions view survives repeated changes and renders a saved denied grant')

    # Sidebar rows retain their visual positions when an older chat is selected.
    data = work/'native-order'
    for index, id in enumerate(('oldest','middle','newest')):
        path = data/'sessions'/id;path.mkdir(parents=True)
        saved = dict(messages=[dict(role='user',content=id)], cards=[dict(kind='user',text=id)])
        (path/'session.json').write_text(json.dumps(saved))
        os.utime(path/'session.json', (1700000000+index, 1700000000+index))
    (data/'settings.json').write_text(json.dumps(dict(current='newest')))
    events.write_text(json.dumps([event(120,'desktop-session-oldest','desktop_open_session')]))
    layout = work/'order-layout.json'
    result = subprocess.run([str(out/'collie'),'--hidden','--frames','70','--data',str(data),'--fixture',str(fixture),
                             '--events',str(events),'--dump-state',str(work/'ui-state.json'),'--dump-layout',str(layout),
                             '--capture',str(out/'desktop-selection.rgba')],env=env,capture_output=True,timeout=15)
    assert result.returncode==0,(result.returncode,result.stderr)
    state=json.loads((work/'ui-state.json').read_text())
    assert state['session_id']=='oldest'
    expected=['newest','middle','oldest']
    assert [row['id'] for row in state['sessions']]==expected
    boxes={row['key']:row for row in json.loads(layout.read_text())}
    assert [boxes['desktop-session-'+id]['y'] for id in expected]==sorted(boxes['desktop-session-'+id]['y'] for id in expected)
    Image.frombytes('RGBA',(1280,860),(out/'desktop-selection.rgba').read_bytes()).save(out/'desktop-selection.png')
    passed('selecting an older chat in the native sidebar keeps its row in place through idle redraws')

    # Hold actual service loading back long enough to capture the frame shown
    # before any new conversation data can arrive. No external request/window.
    slow = work/'slow-service.py'
    slow.write_text('import argparse,asyncio,sys\nfrom pathlib import Path\n'
                    f'sys.path.insert(0,{str(ROOT/"apps/collie/desktop")!r})\n'
                    'from service import Desktop,main\n'
                    'original=Desktop._open_session\n'
                    'async def delayed(self,id=None,project_id=None):\n'
                    ' if self.root is not None: await asyncio.sleep(0.8)\n'
                    ' return await original(self,id,project_id)\n'
                    'Desktop._open_session=delayed\n'
                    'p=argparse.ArgumentParser()\n'
                    'for key in ("engine","data","auth","fixture"):p.add_argument("--"+key,type=Path)\n'
                    'asyncio.run(main(p.parse_args()))\n')
    # The old chat's draft must be journaled before the switch, rather than
    # queued afterward and accidentally saved into the target conversation.
    oldest = data/'sessions'/'oldest'/'session.json'
    saved=json.loads(oldest.read_text());saved['navigation']=dict(page='chat',draft='Keep with oldest')
    atomic(oldest,json.dumps(saved).encode())
    events.write_text(json.dumps([event(120,'desktop-session-middle','desktop_open_session')]))
    result=subprocess.run([str(out/'collie-desktop'),'--service',str(slow),'--hidden','--frames','35','--data',str(data),
                           '--fixture',str(fixture),'--events',str(events),'--dump-state',str(work/'ui-state.json'),
                           '--dump-layout',str(layout),'--capture',str(out/'desktop-selection-loading.rgba')],env=env,capture_output=True,timeout=15)
    assert result.returncode==0,(result.returncode,result.stderr)
    state=json.loads((work/'ui-state.json').read_text());boxes={row['key']:row for row in json.loads(layout.read_text())}
    assert state['session_id']=='oldest' and state['pending_session_id']=='middle'
    assert 'desktop-session-loading-label' in boxes and 'card-0-user' not in boxes and 'composer-draft' not in boxes
    image=Image.frombytes('RGBA',(1280,860),(out/'desktop-selection-loading.rgba').read_bytes())
    for id,color in [('middle',(40,56,45)),('oldest',(21,28,33))]:
        box=boxes['desktop-session-'+id]
        assert image.getpixel((box['x']+box['width']//2,box['y']+3))[:3]==color
    image.save(out/'desktop-selection-loading.png')
    assert json.loads(oldest.read_text())['navigation']['draft']=='Keep with oldest'
    assert not json.loads((data/'sessions'/'middle'/'session.json').read_text())['navigation'].get('draft')
    passed('native sidebar highlights the chosen chat before a delayed load completes and keeps the outgoing draft in its own conversation')

    # Render actual provider-produced summary cards in the native desktop view.
    data = work/'thinking-data'
    events.write_text('[]')
    result = subprocess.run([str(out/'collie'),'--hidden','--frames','45','--data',str(data),'--fixture',str(fixture),
                             '--events',str(events),'--dump-state',str(work/'ui-state.json'),'--dump-layout',str(layout),
                             '--capture',str(out/'desktop-thinking.rgba')],env=env,capture_output=True,timeout=15)
    assert result.returncode==0,(result.returncode,result.stderr)
    boxes={row['key']:row for row in json.loads(layout.read_text())}
    assert 'card-thinking-0-title' in boxes and 'card-thinking-0-preview' in boxes
    assert 'card-1-body' not in boxes
    panel=boxes['card-thinking-0'];scroll=boxes['chat-scroll']
    assert panel['height']>40 and panel['y']>=scroll['y'] and panel['y']+panel['height']<=scroll['y']+scroll['height']
    Image.frombytes('RGBA',(1280,860),(out/'desktop-thinking.rgba').read_bytes()).save(out/'desktop-thinking.png')
    events.write_text(json.dumps([event(100,'card-thinking-0-toggle','fold')]))
    result = subprocess.run([str(out/'collie'),'--hidden','--frames','45','--data',str(data),'--fixture',str(fixture),
                             '--events',str(events),'--dump-layout',str(layout)],env=env,capture_output=True,timeout=15)
    assert result.returncode==0,(result.returncode,result.stderr)
    boxes={row['key']:row for row in json.loads(layout.read_text())}
    assert 'card-1-body' in boxes and 'card-2-body' in boxes
    passed('native desktop shows the returned thinking-summary preview and expands the full summary while keeping the answer separate')

    data=work/'native-markdown';path=data/'sessions'/'game';path.mkdir(parents=True)
    body='## Your Tetris game\n\nCreated [**tetris.html**](tetris.html) — a self-contained game with:\n\n- *Keyboard* and on-screen controls\n- Next-piece preview and ghost piece\n- Score, levels, and saved best score\n- ~~Old controls~~ replaced by `arrow keys`\n\nOpen the file link and click **Start / Restart** to play.\n\n[Read the guide](https://example.com/guide).'
    (path/'session.json').write_text(json.dumps(dict(messages=[dict(role='user',content='Make a Tetris game')],cards=[dict(kind='user',text='Make a Tetris game'),dict(kind='assistant',text=body)])))
    (data/'settings.json').write_text(json.dumps(dict(current='game')));events.write_text('[]')
    result=subprocess.run([str(out/'collie'),'--hidden','--frames','45','--data',str(data),'--fixture',str(fixture),
                           '--events',str(events),'--dump-layout',str(layout),'--capture',str(out/'desktop-markdown.rgba')],env=env,capture_output=True,timeout=15)
    assert result.returncode==0,(result.returncode,result.stderr)
    boxes={row['key']:row for row in json.loads(layout.read_text())}
    assert boxes['card-1-body']['height']>200 and boxes['composer-draft']['focused']
    Image.frombytes('RGBA',(1280,860),(out/'desktop-markdown.rgba').read_bytes()).save(out/'desktop-markdown.png')
    passed('native desktop renders formatted messages, workspace links and the focused composer together')

    # Reproduce a live request with no summary output during the capture window.
    waiting=work/'waiting-fixture.json'
    waiting.write_text(json.dumps([dict(events=[*[dict(type='response.in_progress') for _ in range(120)],completed(message('Done'))])]))
    events.write_text(json.dumps([event(100,'composer-draft','draft','How does it work?','change'),event(140,'composer-send','send')]))
    result=subprocess.run([str(out/'collie'),'--hidden','--frames','45','--data',str(work/'native-thinking-waiting'),'--fixture',str(waiting),
                           '--events',str(events),'--dump-layout',str(layout),'--dump-state',str(work/'waiting-state.json'),
                           '--capture',str(out/'desktop-thinking-waiting.rgba')],env=env,capture_output=True,timeout=15)
    assert result.returncode==0,(result.returncode,result.stderr)
    state=json.loads((work/'waiting-state.json').read_text());boxes={row['key']:row for row in json.loads(layout.read_text())}
    assert state['busy'] and not state.get('live',{}).get('summaries') and not any(c['kind']=='thinking' for c in state['cards'])
    panel=boxes['card-thinking-0'];scroll=boxes['chat-scroll']
    assert panel['height']>40 and panel['y']>=scroll['y'] and panel['y']+panel['height']<=scroll['y']+scroll['height']
    assert 'card-thinking-0-title' in boxes and 'card-thinking-0-preview' in boxes
    Image.frombytes('RGBA',(1280,860),(out/'desktop-thinking-waiting.rgba').read_bytes()).save(out/'desktop-thinking-waiting.png')
    passed('a real native composer submission shows Thinking while waiting before any summary event arrives')

    data=work/'native-tables';path=data/'sessions'/'table';path.mkdir(parents=True)
    body='| No. | President | Years in office |\n| ---: | :--- | :---: |\n| 1 | George Washington | 1789–1797 |\n| 2 | John Adams | 1797–1801 |\n| 3 | Thomas Jefferson | 1801–1809 |\n| 4 | James Madison | 1809–1817 |\n| 5 | James Monroe | 1817–1825 |\n\nDrag to select cells, then press **Ctrl+C** to copy.'
    (path/'session.json').write_text(json.dumps(dict(messages=[dict(role='user',content='Show these terms as a table')],cards=[dict(kind='user',text='Show these terms as a table'),dict(kind='assistant',text=body)])))
    (data/'settings.json').write_text(json.dumps(dict(current='table')));events.write_text('[]')
    result=subprocess.run([str(out/'collie'),'--hidden','--frames','45','--data',str(data),'--fixture',str(fixture),
                           '--events',str(events),'--dump-layout',str(layout),'--capture',str(out/'desktop-tables.rgba')],env=env,capture_output=True,timeout=15)
    assert result.returncode==0,(result.returncode,result.stderr)
    boxes={row['key']:row for row in json.loads(layout.read_text())};body_box=boxes['card-1-body']
    assert body_box['height']>250
    image=Image.frombytes('RGBA',(1280,860),(out/'desktop-tables.rgba').read_bytes());image.save(out/'desktop-tables.png')
    assert image.getpixel((body_box['x']+2,body_box['y']+2))[:3]==(37,53,46)
    passed('the native Collie message renders a table grid with a shaded header and readable aligned columns')


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--out', type=Path, default=ROOT/'build/collie-desktop')
    a=p.parse_args();out=a.out.resolve();checks=[]
    def passed(text):
        checks.append(text);print('PASS',text,flush=True)
    with tempfile.TemporaryDirectory(prefix='desktop-test-',dir=out) as directory:
        work=Path(directory)
        asyncio.run(integration(out,work,passed))
        asyncio.run(session_order(out,work,passed))
        asyncio.run(session_cache(out,work,passed))
        asyncio.run(thinking_stream(out,work,passed))
        asyncio.run(message_links(out,work,passed))
        native_ui(out,work,passed)
    (out/'desktop-report.json').write_text(json.dumps({'checks':checks,'headless':True,'live_model':False,'physical_devices':False,
                                                      'screenshots':['desktop-chat.png','desktop-permissions.png','desktop-selection.png','desktop-thinking.png','desktop-markdown.png','desktop-thinking-waiting.png','desktop-tables.png']},indent=2)+'\n')
    print(len(checks),'desktop integration groups passed')


if __name__=='__main__': main()
