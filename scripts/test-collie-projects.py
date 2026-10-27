#!/usr/bin/env python3
"""Headless project folders through the real desktop controller and native VM."""
import argparse
import asyncio
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from unittest.mock import AsyncMock, patch

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tests/collie/reference_host'))
from service import Desktop


def completed(item):
    return dict(type='response.completed', response=dict(status='completed', output=[item]))


def message(text):
    return dict(type='message', role='assistant', content=[dict(type='output_text', text=text)])


def tool(source, id):
    return dict(type='custom_tool_call', id=id, call_id=id, name='flexscript', input=source, status='completed')


async def exercise(out, work, passed):
    data = work/'data';fixture = work/'fixture.json';fixture.write_text('[]')
    folder = work/'Tetris playground';folder.mkdir()
    (folder/'existing.txt').write_text('Existing host file')
    other = work/'Other project';other.mkdir()
    d = Desktop(out/'engine', data, fixture=fixture, emit=lambda packet: None)
    try:
        await d.initialize()
        personal = d.root.name
        (d.root/'files'/'old.txt').write_text('Keep the original workspace')
        with patch.object(d, 'choose', new=AsyncMock(return_value=folder)) as choose:
            await d.command(dict(kind='choose_project_folder'))
            choose.assert_awaited_once_with('Choose a project folder', folder=True)
        first = d.project_id;first_chat = d.root.name
        assert first and first_chat != personal and d.files_directory() == folder
        assert d.project_name() == folder.name and len(d.projects.entries) == 1
        assert all(p == 'ask' for p in d.permissions.values())
        await d.command(dict(kind='permission', key='files_write', allowed=False))
        result = await d.call(3, source='fn main(){return fs_write("denied.txt",db_text("No"));}', call_id='denied')
        assert result['exit_code'] == 0 and not (folder/'denied.txt').exists()
        await d.command(dict(kind='permission', key='files_write', allowed=True))
        await d.command(dict(kind='permission', key='files_read', allowed=True))
        result = await d.call(3, source='fn main(){if(!fs_write("game.html",db_text("<title>Tetris</title>"))){return 8;}let v=fs_read("existing.txt",0,32768);if(!v){return 9;}db_io(0,1,db_word(v),db_bytes(v));return 0;}', call_id='host-files')
        assert result['exit_code'] == 0 and result['stdout'] == 'Existing host file', result
        assert (folder/'game.html').read_text() == '<title>Tetris</title>'
        assert not (d.root/'files'/'game.html').exists() and not (folder/'agent.flexdb').exists()
        instructions = (await d.call(1, messages=[dict(role='user', content='Where are my files?')]))['instructions']
        assert str(folder) in instructions and 'initially empty app-private' not in instructions
        passed('chosen host folder is the real VM filesystem, with ordinary file grants and correct model path instructions')

        outside = work/'outside';outside.mkdir();(outside/'secret.txt').write_text('Outside')
        (folder/'escape').symlink_to(outside, target_is_directory=True)
        for path in ('../outside/secret.txt', 'escape/secret.txt'):
            source='fn main(){return fs_read('+json.dumps(path)+',0,100)!=0;}'
            result=await d.call(3, source=source, call_id='outside')
            assert result['exit_code']==0, result
        with patch('service.webbrowser.open', return_value=True) as browser, patch.dict(os.environ, {'COLLIE_HEADLESS':'0'}):
            await d.command(dict(kind='open_link', href='game.html'))
            browser.assert_called_once_with((folder/'game.html').as_uri(), new=2)
        attachment=work/'notes.txt';attachment.write_text('Attached to the project')
        await d.attach(attachment)
        assert (folder/d.attachments[0]['path']).read_text()=='Attached to the project'
        await d.command(dict(kind='read_preview', file=dict(path='game.html', type='file')))
        passed('project file previews, attachments and links use the chosen folder; parent paths and symlink escapes stay bounded')

        await d.command(dict(kind='new_session'))
        second_chat=d.root.name
        assert d.project_id==first and second_chat!=first_chat and d.permissions['files_read']=='ask'
        await d.command(dict(kind='permission', key='files_read', allowed=True))
        await d.command(dict(kind='permission', key='files_write', allowed=True))
        await d.command(dict(kind='permission', key='workers', allowed=True))
        result=await d.call(3, source='fn main(){let v=fs_read("game.html",0,100);if(!v){return 9;}db_io(0,1,db_word(v),db_bytes(v));return 0;}', call_id='shared')
        assert result['stdout']=='<title>Tetris</title>' and result['exit_code']==0
        d.fixture={'main':[completed(tool('fn main(){let id=worker_start("Writer","Save a project file");worker_await(id);return 0;}','parent')),completed(message('Done'))],
                   'workers':{'1':[completed(tool('fn main(){return fs_write("worker.txt",db_text("Worker in project"))-1;}','worker')),completed(message('Saved'))]}}
        await d.command(dict(kind='submit', text='Write from a worker'))
        deadline=asyncio.get_running_loop().time()+12
        while d.tasks:
            assert asyncio.get_running_loop().time()<deadline, 'Worker timed out'
            await asyncio.sleep(0.02)
        assert (folder/'worker.txt').read_text()=='Worker in project'
        passed('new conversations share project files, keep separate grants and database state, and workers use the same host folder')

        with patch.object(d, 'choose', new=AsyncMock(return_value=other)):
            await d.command(dict(kind='choose_project_folder'))
        second=d.project_id;assert second!=first and d.files_directory()==other
        await d.command(dict(kind='select_project', id=first))
        assert d.root.name==second_chat and d.files_directory()==folder
        with patch.object(d, 'choose', new=AsyncMock(return_value=folder)):
            await d.command(dict(kind='choose_project_folder'))
        assert len(d.projects.entries)==2 and d.project_id==first
        with patch.object(d, 'choose', new=AsyncMock(return_value=None)):
            await d.command(dict(kind='choose_project_folder'))
        assert len(d.projects.entries)==2 and d.root.name==second_chat
        await d.command(dict(kind='select_project', id=''))
        assert d.root.name==personal and (d.files_directory()/'old.txt').read_text()=='Keep the original workspace'
        await d.command(dict(kind='select_project', id=first))
        await d.close()
        d=Desktop(out/'engine', data, fixture=fixture, emit=lambda packet: None)
        await d.initialize()
        assert d.project_id==first and d.root.name==second_chat and d.files_directory()==folder
        moved=folder.with_name('temporarily moved');folder.rename(moved)
        try:
            await d.facts()  # History/context remain usable if a drive is absent.
            (d.root/'files'/'game.html').write_text('Do not fall back here')
            result=await d.call(3, source='fn main(){return fs_read("game.html",0,100)!=0;}', call_id='missing-folder')
            assert result['exit_code']==0
        finally:
            moved.rename(folder)
        passed('projects reopen the latest chat, survive restart, deduplicate folders, preserve personal chats and never fall back when a folder is missing')
    finally:
        await d.close()
    return data, fixture


def capture(out, work, data, fixture, passed):
    events=work/'events.json'
    events.write_text(json.dumps([
        dict(at=80, request=dict(action='event', event=dict(key='desktop-collapse', action='desktop_sidebar', action_id=0, type='click'))),
        dict(at=160, request=dict(action='event', event=dict(key='chat-project', action='projects', action_id=0, type='click')))]))
    env=dict(os.environ, SDL_VIDEODRIVER='dummy', COLLIE_HEADLESS='1');env.pop('DISPLAY', None);env.pop('WAYLAND_DISPLAY', None)
    state=work/'state.json';layout=work/'layout.json';raw=out/'desktop-projects.rgba'
    result=subprocess.run([str(out/'collie'),'--hidden','--frames','45','--data',str(data),'--fixture',str(fixture),
                           '--events',str(events),'--dump-state',str(state),'--dump-layout',str(layout),'--capture',str(raw)],env=env,capture_output=True,timeout=15)
    assert result.returncode==0,(result.returncode,result.stderr)
    facts=json.loads(state.read_text());boxes={b['key']:b for b in json.loads(layout.read_text())}
    assert facts['page']=='projects' and boxes['projects-add']['focused']
    assert len([key for key in boxes if key.startswith('project-') and key.endswith('-path')])==2
    assert boxes['projects-panel']['width']<=560
    Image.frombytes('RGBA',(1280,860),raw.read_bytes()).save(out/'desktop-projects.png')
    passed('native project picker shows folders, the selected project and bounded centered layout with modal keyboard focus')
    other=next(row['id'] for row in facts['projects'] if row['name']=='Other project')
    events.write_text(json.dumps([
        dict(at=100,request=dict(action='event',event=dict(key='project-'+other,action='select_project',action_id=0,type='click'))),
        dict(at=220,request=dict(action='event',event=dict(key='desktop-toggle',action='desktop_sidebar',action_id=0,type='click'))),
        dict(at=350,request=dict(action='event',event=dict(key='desktop-new',action='new_session',action_id=0,type='click')))]))
    result=subprocess.run([str(out/'collie'),'--hidden','--frames','60','--data',str(data),'--fixture',str(fixture),
                           '--events',str(events),'--dump-state',str(state),'--dump-layout',str(layout)],env=env,capture_output=True,timeout=15)
    assert result.returncode==0,(result.returncode,result.stderr)
    facts=json.loads(state.read_text());boxes={b['key']:b for b in json.loads(layout.read_text())}
    assert facts['project_id']==other and facts['page']=='chat'
    rows=[r for r in facts['sessions'] if r['project_id']==other]
    assert len(rows)==2 and all('desktop-session-'+r['id'] in boxes for r in rows)
    assert all('desktop-session-'+r['id'] in boxes for r in facts['sessions'])
    saved=json.loads((data/'sessions'/facts['session_id']/'session.json').read_text())
    assert saved['project_id']==other
    events.write_text(json.dumps([dict(at=100, request=dict(action='event', event=dict(key='chat-project', action='projects', action_id=0, type='click')))]))
    result=subprocess.run([str(out/'collie'),'--hidden','--frames','40','--width','800','--height','700','--data',str(data),'--fixture',str(fixture),
                           '--events',str(events),'--dump-layout',str(layout)],env=env,capture_output=True,timeout=15)
    assert result.returncode==0,(result.returncode,result.stderr)
    boxes={b['key']:b for b in json.loads(layout.read_text())};panel=boxes['projects-panel']
    assert panel['y']>=0 and panel['y']+panel['height']<=700 and boxes['projects-add']['focused']
    passed('native project selection and new-chat actions persist membership, retain project groups and remain usable in a narrow window')


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',type=Path,default=ROOT/'build/collie-desktop')
    out=p.parse_args().out.resolve();checks=[]
    def passed(text):checks.append(text);print('PASS',text,flush=True)
    with tempfile.TemporaryDirectory(prefix='projects-',dir=out) as tmp:
        work=Path(tmp);data,fixture=asyncio.run(exercise(out,work,passed));capture(out,work,data,fixture,passed)
    (out/'projects-report.json').write_text(json.dumps(dict(checks=checks,headless=True,live_model=False),indent=2)+'\n')
    print(len(checks),'project groups passed')


if __name__=='__main__':main()
