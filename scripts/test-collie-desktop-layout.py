#!/usr/bin/env python3
"""Measure actual native layout and exercise resize/keyboard input headlessly."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile
from PIL import Image

ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',type=Path,default=ROOT/'build/collie-desktop')
a=p.parse_args();out=a.out.resolve();checks=[]

def passed(text):checks.append(text);print('PASS',text,flush=True)
def event(at,key,action,value=None,type='click',id=0):
    return dict(at=at,request=dict(action='event',event=dict(key=key,action=action,action_id=id,value=value,type=type)))
def key(at,code):return dict(at=at,request=dict(action='native_key',code=code,modifiers=64))

with tempfile.TemporaryDirectory(prefix='layout-',dir=out) as directory:
    work=Path(directory);input_fixture=work/'input.so'
    subprocess.run(['cc','-shared','-fPIC','-O2',str(ROOT/'tests/ui/desktop-events.c'),'-o',str(input_fixture),'-ldl'],check=True)
    data=work/'data';sessions=data/'sessions';sessions.mkdir(parents=True)
    fixture=work/'fixture.json';fixture.write_text('[]')
    titles=['Desktop workspace','Plan a weekend trip','Review the compiler','Organize research','Write a project outline']
    for i,title in enumerate(titles):
        path=sessions/f'conversation-{i}';path.mkdir();(path/'files').mkdir()
        messages=[dict(role='user',content=title),dict(role='assistant',content='A focused place for your notes and next steps.')]
        cards=[dict(kind='user',text='Help me organize this project into a few clear steps.'),
               dict(kind='assistant',text='## A practical starting point\n\n1. Gather the files and decide what you want to achieve.\n2. Work through one small task at a time.\n3. Review the result and choose the next step.\n\nYou can attach documents, return to earlier conversations, or ask a worker to investigate a separate question.')]
        (path/'session.json').write_text(json.dumps(dict(messages=messages,archive=messages,cards=cards)))
    (data/'settings.json').write_text(json.dumps(dict(current='conversation-0')))
    env=dict(os.environ,SDL_VIDEODRIVER='dummy',COLLIE_HEADLESS='1');env.pop('DISPLAY',None);env.pop('WAYLAND_DISPLAY',None)
    def run(name,width=1280,height=860,events=None):
        script=work/(name+'-events.json');script.write_text(json.dumps(events or []))
        state=out/(name+'-state.json');layout=out/(name+'-layout.json');raw=out/(name+'.rgba')
        command=[str(out/'collie'),'--hidden','--frames','75','--width',str(width),'--height',str(height),'--data',str(data),
                 '--fixture',str(fixture),'--events',str(script),'--dump-state',str(state),'--dump-layout',str(layout),'--capture',str(raw)]
        r=subprocess.run(command,env=env,capture_output=True,timeout=20)
        assert r.returncode==0,(name,r.returncode,r.stderr.decode())
        facts=json.loads(state.read_text());boxes={row['key']:row for row in json.loads(layout.read_text())}
        w=facts['viewport_width'];h=facts['viewport_height']
        pixels=raw.read_bytes();assert len(pixels)==w*h*4
        Image.frombytes('RGBA',(w,h),pixels).save(out/(name+'.png'))
        return facts,boxes
    def assert_chat(facts,boxes):
        w=facts['viewport_width'];h=facts['viewport_height'];main=boxes['desktop-main'];composer=boxes['composer'];transcript=boxes['chat-transcript']
        assert main['y']==0 and main['height']==h,(main,h)
        assert main['x']+main['width']==w,main
        assert 240<=transcript['width']<=820,transcript
        assert abs(transcript['x']+transcript['width']/2-main['x']-main['width']/2)<=1
        assert composer['x']==transcript['x'] and composer['width']==transcript['width']
        assert composer['y']+composer['height']<=h and composer['y']>h-230,composer
        editor=boxes['composer-draft'];assert editor['width']>150 and editor['y']+editor['height']<=h
    facts,boxes=run('desktop-layout-chat',1600,1000)
    assert_chat(facts,boxes)
    sidebar=boxes['workspace-sidebar'];assert sidebar['x']==0 and sidebar['y']==0 and sidebar['height']==1000
    assert boxes['desktop-sidebar']['y']==boxes['workspace-sidebar-modes']['height']
    assert 'desktop-session-conversation-4' in boxes
    assert boxes['card-0-user']['y']<180,boxes['card-0-user']
    passed('wide desktop keeps persistent conversations, full-height panes, readable centered messages and a visible composer')
    row=boxes['composer-input-row'];pixel=(row['x']+row['width']//2,row['y'])
    assert boxes['composer-draft']['focused'] and Image.open(out/'desktop-layout-chat.png').getpixel(pixel)[:3]==(173,217,143)
    body=boxes['card-1-body'];sx=body['x']-12;sy=body['y']+15;ex=body['x']+180;ey=body['y']+75
    def pointer(at,kind,a,b,c,d=0):return dict(at=at,request=dict(action='native_mouse',fixture=str(input_fixture),kind=kind,a=a,b=b,c=c,d=d))
    facts,boxes=run('desktop-layout-gutter-selection',1600,1000,events=[pointer(100,1025,1,sx,sy),pointer(160,1024,ex,ey,ex-sx,ey-sy),pointer(200,1026,1,ex,ey),key(240,6)])
    selection=boxes['card-1-body'];assert selection['focused'] and selection['anchor']==0 and selection['caret']>0
    assert facts['page']=='chat' and not facts['draft']
    passed('native pointer drag from the transcript padding selects message text without requiring a press on a glyph')
    facts,boxes=run('desktop-layout-access',events=[event(100,'desktop-settings','menu'),event(140,'settings-nav-access','settings_section',id=1)])
    assert facts['page']=='settings' and facts['settings_section']=='access' and len(facts['permission_entries'])==11
    assert 'allow-nfc' not in boxes and 'allow-bluetooth' not in boxes and 'allow-uwb' not in boxes
    choice=boxes['allow-files_read'];row=boxes['permission-row-files_read']
    assert choice['height']<=40 and choice['x']>row['x']+row['width']/2
    assert choice['y']>=row['y'] and choice['y']+choice['height']<=row['y']+row['height']
    passed('desktop workspace access lists only implemented grants and aligns compact choices beside their descriptions')
    policy=facts['policy'];worker=boxes['desktop-workers'];wx=worker['x']+worker['width']//2;wy=worker['y']+worker['height']//2
    facts,boxes=run('desktop-layout-access-workers',events=[pointer(120,1025,1,wx,wy,0),pointer(180,1026,1,wx,wy,0)])
    assert facts['page']=='workers' and facts['policy']==policy
    passed('a native mouse click on Workers from restored workspace access opens Workers without crashing or changing any grant')
    facts,boxes=run('desktop-layout-settings-model',events=[event(100,'desktop-settings','menu'),event(160,'settings-nav-model','settings_section')])
    assert facts['page']=='settings' and 'settings-title' in boxes and 'desktop-permissions' not in boxes
    assert boxes['settings-navigation']['x']+boxes['settings-navigation']['width']<=boxes['settings-scroll']['x']
    draft=facts['draft'];policy=facts['policy']
    facts,boxes=run('desktop-layout-settings-account',events=[event(100,'settings-nav-account','settings_section',id=2)])
    assert facts['settings_section']=='account' and 'settings-account-login' in boxes
    facts,boxes=run('desktop-layout-settings-narrow',800,700,events=[event(100,'settings-nav-access','settings_section',id=1)])
    assert boxes['settings-navigation']['width']>600 and boxes['settings-scroll']['y']>boxes['settings-navigation']['y']
    assert facts['policy']==policy and facts['draft']==draft
    facts,boxes=run('desktop-layout-settings-return',events=[event(100,'settings-nav-model','settings_section'),event(160,'settings-model-change','model'),event(260,'model-option-1','choose_model',id=1)])
    assert facts['page']=='settings' and facts['model']=='gpt-6-astra' and 'settings-model-current' in boxes
    passed('dedicated settings navigate model, access and account; narrow windows use tabs and selecting a model returns to settings without losing the draft')
    facts,boxes=run('desktop-layout-settings-open-chat',events=[event(100,'desktop-session-conversation-1','desktop_open_session'),event(300,'desktop-session-conversation-0','desktop_open_session')])
    assert facts['page']=='chat' and facts['session_id']=='conversation-0' and facts['draft']==draft
    passed('selecting chats leaves settings and restores the conversation rather than reopening the settings page')
    # Return to chat and route real SDL Ctrl+, to the model dialog.
    facts,boxes=run('desktop-layout-model',events=[dict(at=100,request=dict(action='back')),key(160,54)])
    assert facts['page']=='model' and boxes['model-panel']['width']<=560 and boxes['model-input']['focused']
    assert 'model-network-wifi' not in boxes
    main=boxes['desktop-main'];panel=boxes['model-panel']
    assert abs(panel['x']+panel['width']/2-main['x']-main['width']/2)<=1
    assert panel['y']>80 and panel['y']+panel['height']<facts['viewport_height']-40
    passed('desktop settings open as centered dialogs and actual Ctrl+, selects the model screen')
    tabs=[dict(at=100+i*45,request=dict(action='native_key',code=43,modifiers=0)) for i in range(5)]
    facts,boxes=run('desktop-layout-dialog-tabs',events=tabs)
    assert boxes['model-option-0']['focused'] and not boxes['desktop-search']['focused']
    passed('dialog focus starts in the model field and Tab stays inside its controls')
    facts,boxes=run('desktop-model-search',events=[event(100,'model-input','model_query','gpt 6 astra','change')])
    assert 'model-option-1' in boxes and 'model-option-0' not in boxes
    facts,boxes=run('desktop-model-selected',events=[dict(at=120,request=dict(action='native_key',code=40,modifiers=0))])
    assert facts['model']=='gpt-6-astra' and facts['page']=='chat'
    facts,boxes=run('desktop-model-reselect',events=[key(100,54),dict(at=160,request=dict(action='native_text',text='sol',fixture=str(input_fixture))),dict(at=220,request=dict(action='native_key',code=40,modifiers=0))])
    assert facts['model']=='gpt-6.1-sol' and facts['page']=='chat'
    passed('model search filters Sol/Astra and native Enter selects and persists the chosen model')
    facts,boxes=run('desktop-layout-editing',events=[dict(at=60,request=dict(action='back')),
                    event(100,'composer-draft','draft','abc','change'),
                    dict(at=140,request=dict(action='native_key',code=80,modifiers=0)),
                    dict(at=180,request=dict(action='native_text',text='X',fixture=str(input_fixture))),
                    dict(at=220,request=dict(action='native_text',text='Y',fixture=str(input_fixture)))])
    assert facts['draft']=='abXYc',facts['draft']
    passed('native text events edit in the middle of a controlled draft without moving the caret to the end')

    facts,boxes=run('desktop-layout-narrow',800,700,events=[dict(at=100,request=dict(action='back'))])
    assert_chat(facts,boxes);assert 'desktop-sidebar' not in boxes and 'workspace-toggle-sidebar' in boxes
    passed('narrow windows use compact navigation while keeping the editor and full-height chat usable')
    draft='A draft that survives resizing — 中文'
    facts,boxes=run('desktop-layout-resized',1600,1000,events=[event(120,'composer-draft','draft',draft,'change'),
                    dict(at=160,request=dict(action='native_resize',width=780,height=700)),key(240,14),
                    dict(at=300,request=dict(action='back')),dict(at=360,request=dict(action='native_resize',width=1280,height=860))])
    assert_chat(facts,boxes);assert facts['draft']==draft and facts['viewport_width']==1280 and 'desktop-sidebar' in boxes
    passed('actual SDL resizes across the sidebar breakpoint preserve Unicode drafts and recover the wide layout')
    facts,boxes=run('desktop-layout-collapsed',events=[key(160,5)])
    assert facts['sidebar_collapsed']==1 and 'desktop-sidebar' not in boxes;assert_chat(facts,boxes)
    facts,boxes=run('desktop-layout-restored')
    assert facts['sidebar_collapsed']==1 and 'desktop-sidebar' not in boxes
    facts,boxes=run('desktop-layout-search',events=[key(120,5),key(200,14)])
    assert facts['sidebar_collapsed']==0 and 'desktop-search' in boxes and boxes['desktop-search']['focused']
    row=boxes['composer-input-row'];pixel=(row['x']+row['width']//2,row['y'])
    assert Image.open(out/'desktop-layout-search.png').getpixel(pixel)[:3]==(44,53,59)
    passed('Ctrl+B toggles the sidebar, its preference survives restart, and Ctrl+K focuses conversation search')
    facts,boxes=run('desktop-layout-welcome',events=[key(140,17)])
    active_prefix=f"chat-panel-{facts['chat_active']}::"
    boxes={k.removeprefix(active_prefix) if k.startswith(active_prefix) else k:v for k,v in boxes.items()}
    assert facts['page']=='chat' and not facts['cards'] and 'desktop-welcome' in boxes
    assert facts['session_id']!='conversation-0'
    assert_chat(facts,boxes)
    passed('Ctrl+N opens a fresh desktop conversation with a centered welcome screen and updates the sidebar')
(out/'desktop-layout-report.json').write_text(json.dumps(dict(checks=checks,headless=True,physical_display=False),indent=2)+'\n')
print(len(checks),'desktop layout groups passed')
