#!/usr/bin/env python3
"""Native sidebar modes, cross-project selection and preference persistence."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time

from PIL import Image

ROOT=Path(__file__).resolve().parents[1]


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',type=Path,default=ROOT/'build/collie-desktop')
    out=p.parse_args().out.resolve();checks=[]
    def passed(text):checks.append(text);print('PASS',text,flush=True)
    with tempfile.TemporaryDirectory(prefix='sidebar-',dir=out) as tmp:
        work=Path(tmp);data=work/'data';data.mkdir();fixture=work/'fixture.json';fixture.write_text('[]')
        projects=[dict(id='alpha',name='Collie desktop',path=str(work/'Collie desktop')),
                  dict(id='beta',name='Garden planner',path=str(work/'Garden planner'))]
        for row in projects:Path(row['path']).mkdir()
        (data/'projects.json').write_text(json.dumps(projects))
        entries=[('alpha-plan','alpha','Plan the desktop layout','A clear sidebar and a readable conversation.'),
                 ('beta-notes','beta','Plan next spring','Choose plants and organize the garden.'),
                 ('personal','','Weekend notes','A few ideas to come back to.'),
                 ('alpha-rendering','alpha','Improve text rendering','Check selection, fonts, and message tables.')]
        activity=int(time.time()*1000)
        for i,(id,project,title,reply) in enumerate(entries):
            path=data/'sessions'/id;path.mkdir(parents=True)
            (path/'session.json').write_text(json.dumps(dict(project_id=project,last_activity=activity-i*3600000,
                messages=[dict(role='user',content=title),dict(role='assistant',content=reply)],
                cards=[dict(kind='user',text=title),dict(kind='assistant',text=reply)],navigation=dict(page='chat',draft='Draft for '+id))))
        (data/'settings.json').write_text(json.dumps(dict(current='alpha-plan')))
        env=dict(os.environ,SDL_VIDEODRIVER='dummy',COLLIE_HEADLESS='1');env.pop('DISPLAY',None);env.pop('WAYLAND_DISPLAY',None)
        native=work/'input.so'
        subprocess.run(['cc','-shared','-fPIC','-O2',str(ROOT/'tests/ui/desktop-events.c'),'-o',str(native),'-ldl'],check=True)
        def pointer(at,kind,a,b,c=0):return dict(at=at,request=dict(action='native_mouse',fixture=str(native),kind=kind,a=a,b=b,c=c,d=0))
        def event(at,key,action,id=0,value=None,type='click'):
            return dict(at=at,request=dict(action='event',event=dict(key=key,action=action,action_id=id,value=value,type=type)))
        def run(name,events=()):
            script=work/'events.json';script.write_text(json.dumps(events));state=work/'state.json';layout=work/'layout.json';raw=out/(name+'.rgba')
            result=subprocess.run([str(out/'collie'),'--hidden','--frames','65','--width','1280','--height','1000',
                '--data',str(data),'--fixture',str(fixture),'--events',str(script),'--dump-state',str(state),'--dump-layout',str(layout),'--capture',str(raw)],
                env=env,capture_output=True,timeout=20)
            assert result.returncode==0,(name,result.returncode,result.stderr)
            facts=json.loads(state.read_text());boxes={b['key']:b for b in json.loads(layout.read_text())}
            image=Image.frombytes('RGBA',(facts['viewport_width'],facts['viewport_height']),raw.read_bytes());image.save(out/(name+'.png'))
            return facts,boxes,image
        facts,boxes,image=run('desktop-sidebar-projects')
        assert facts['sidebar_mode']=='projects' and all('sidebar-group-'+id in boxes for id in ('','alpha','beta'))
        assert boxes['sidebar-group-alpha']['y']<boxes['desktop-session-alpha-plan']['y']<boxes['desktop-session-alpha-rendering']['y']<boxes['sidebar-group-beta']['y']
        brand=boxes['desktop-brand'];new=boxes['desktop-new'];project=boxes['desktop-new-project']
        assert brand['y']<=new['y']<brand['y']+brand['height'] and new['x']+new['width']<=project['x']
        assert 'sidebar-projects-add' in boxes and 'sidebar-new-alpha' in boxes
        passed('grouped sidebar shows project sections and places distinct New chat/New project icons at the top plus a project-heading add button')
        facts,boxes,image=run('desktop-sidebar-timeline',[event(100,'sidebar-mode-timeline','sidebar_mode',1)])
        assert facts['sidebar_mode']=='timeline' and 'sidebar-group-alpha' not in boxes
        ids=[row[0] for row in entries]
        assert [boxes['desktop-session-'+id]['y'] for id in ids]==sorted(boxes['desktop-session-'+id]['y'] for id in ids)
        assert all('desktop-session-'+id+'-project' in boxes and 'desktop-session-'+id+'-date' in boxes for id in ids)
        passed('timeline lists all projects and personal chats in saved activity order with project names and dates')
        facts,boxes,_=run('desktop-sidebar-cross-project',[event(100,'desktop-session-beta-notes','desktop_open_session')])
        assert facts['sidebar_mode']=='timeline' and facts['session_id']=='beta-notes' and facts['project_id']=='beta'
        assert all('desktop-session-'+id in boxes for id in ids)
        settings=json.loads((data/'settings.json').read_text());assert settings['sidebar_mode']=='timeline'
        assert json.loads((data/'sessions/alpha-plan/session.json').read_text())['navigation']['draft']=='Draft for alpha-plan'
        facts,_,_=run('desktop-sidebar-timeline-restored')
        assert facts['sidebar_mode']=='timeline' and facts['project_id']=='beta'
        passed('mode survives cross-project chat selection and restart without changing the outgoing conversation draft')
        facts,boxes,_=run('desktop-sidebar-groups-restored',[
            event(100,'sidebar-mode-projects','sidebar_mode'),event(180,'sidebar-fold-beta','sidebar_group'),
            event(220,'sidebar-fold-alpha','sidebar_group'),event(300,'sidebar-new-alpha','project_new_chat')])
        assert facts['sidebar_mode']=='projects' and facts['sidebar_closed']['beta'] and facts['project_id']=='alpha'
        assert facts['session_id'] not in ids and 'desktop-session-beta-notes' not in boxes
        assert not facts['sidebar_closed']['alpha'] and 'desktop-session-'+facts['session_id'] in boxes
        assert json.loads((data/'sessions'/facts['session_id']/'session.json').read_text())['project_id']=='alpha'
        facts,boxes,_=run('desktop-sidebar-fold-restored')
        assert facts['sidebar_mode']=='projects' and facts['sidebar_closed']['beta'] and 'desktop-session-beta-notes' not in boxes
        passed('project-group New chat creates in that project; collapsed groups and mode remain global across chats and restart')
        facts,boxes,_=run('desktop-sidebar-search',[event(100,'desktop-search','query',value='Garden',type='change')])
        assert 'desktop-session-beta-notes' in boxes and 'desktop-session-alpha-plan' not in boxes
        assert facts['sidebar_closed']['beta'], 'Search should reveal results without changing the saved collapse preference'
        passed('search finds project names and reveals matching chats inside collapsed groups')
        facts,boxes,_=run('desktop-sidebar-resized',[
            event(80,'desktop-search','query',value='',type='change'),
            pointer(120,1024,255,450),pointer(160,1025,1,255,450),
            pointer(200,1024,403,450),pointer(240,1026,1,403,450)])
        assert boxes['desktop-sidebar']['width']==400 and boxes['desktop-main']['x']==406,boxes['desktop-sidebar']
        assert json.loads((data/'settings.json').read_text())['sidebar_width']==400
        facts,boxes,image=run('desktop-sidebar-resize-restored',[pointer(120,1024,403,450),event(160,'sidebar-fold-beta','sidebar_group'),event(220,'desktop-session-beta-notes','desktop_open_session')])
        assert facts['session_id']=='beta-notes' and boxes['desktop-sidebar']['width']==400
        passed('native divider drag resizes both panes and keeps its width through chat switching and restart')
        facts,boxes,_=run('desktop-sidebar-resize-limits',[
            pointer(100,1025,1,403,450),pointer(140,1024,-100,450),pointer(180,1026,1,-100,450),
            pointer(240,1025,1,223,450),pointer(280,1024,2000,450),pointer(320,1026,1,2000,450)])
        assert boxes['desktop-sidebar']['width']==520 and boxes['desktop-main']['width']>=520
        facts,boxes,_=run('desktop-sidebar-resize-window',[
            dict(at=100,request=dict(action='native_resize',width=960,height=1000))])
        assert boxes['desktop-sidebar']['width']==434 and boxes['desktop-main']['width']==520
        assert json.loads((data/'settings.json').read_text())['sidebar_width']==520
        facts,boxes,_=run('desktop-sidebar-resize-wide')
        assert boxes['desktop-sidebar']['width']==520
        passed('dragging outside either pane clamps the width; smaller windows preserve chat space without losing the preferred sidebar width')
        facts,boxes,_=run('desktop-sidebar-resize-focus',[
            pointer(100,1025,1,523,450),pointer(140,1024,363,450),
            pointer(180,512,13,0),pointer(220,1024,803,450),pointer(260,1026,1,803,450),
            pointer(300,512,12,0),pointer(340,768,79,0)])
        assert boxes['desktop-sidebar']['width']==376 and boxes['desktop-sidebar-divider']['focused']
        assert json.loads((data/'settings.json').read_text())['sidebar_width']==376
        passed('focus loss releases the resize capture and a focused divider supports keyboard width adjustment')
        for i in range(24):
            path=data/'sessions'/('overflow-'+str(i));path.mkdir(parents=True)
            (path/'session.json').write_text(json.dumps(dict(project_id='',last_activity=activity+i*1000,
                messages=[dict(role='user',content='Earlier conversation '+str(i))],
                cards=[dict(kind='user',text='Earlier conversation '+str(i))])))
        settings=json.loads((data/'settings.json').read_text());settings.update(sidebar_width=252,sidebar_mode='timeline')
        (data/'settings.json').write_text(json.dumps(settings))
        facts,baseline,image=run('desktop-sidebar-scrollbar')
        pane=baseline['desktop-sessions-scroll'];right=pane['x']+pane['width'];top=pane['y'];bottom=top+pane['height']
        assert pane['content_height']>pane['height'] and right==baseline['desktop-sidebar']['width']
        assert image.getpixel((right-6,top+8))[:3]==(112,135,128),'Sidebar thumb must be visible without hover'
        session=facts['session_id']
        facts,boxes,_=run('desktop-sidebar-scrollbar-drag',[
            pointer(100,1025,1,right-6,top+10),pointer(160,1024,right-6,bottom-1),pointer(220,1026,1,right-6,bottom-1)])
        pane=boxes['desktop-sessions-scroll'];assert pane['scroll_y']==pane['content_height']-pane['height']
        assert facts['session_id']==session and boxes['chat-scroll']['scroll_y']==baseline['chat-scroll']['scroll_y']
        for key in ('desktop-search','desktop-sidebar-mode','desktop-tools'):
            assert boxes[key]['y']==baseline[key]['y']
        passed('the left chat list has a visible right-edge scrollbar; dragging reaches older chats without moving the conversation, search or tools')
    (out/'sidebar-report.json').write_text(json.dumps(dict(checks=checks,headless=True,live_model=False),indent=2)+'\n')
    print(len(checks),'sidebar groups passed')


if __name__=='__main__':main()
