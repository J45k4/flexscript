#!/usr/bin/env python3
"""Correctness smoke checks on an explicitly selected private Wayland display.

Replay tests exercise GUI/UI integration, not OS pointer/key delivery or latency.
The compositor's actual seat/keymap/focus delivery is checked separately below.
"""
import argparse
import json
import os
from pathlib import Path
import stat
import subprocess
import tempfile

ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--benchmark',type=Path,required=True)
p.add_argument('--collie',type=Path)
p.add_argument('--runtime',type=Path,required=True)
p.add_argument('--display',required=True)
p.add_argument('--require-seat',action='store_true')
p.add_argument('--native-feedback',action='store_true')
p.add_argument('--out',type=Path,default=ROOT/'build/migration/wayland-ui-tests')
a=p.parse_args();out=a.out.resolve();out.mkdir(parents=True,exist_ok=True)
runtime=a.runtime.resolve();st=runtime.stat()
assert st.st_uid==os.getuid() and stat.S_IMODE(st.st_mode)==0o700,'Use an owned private runtime directory'
assert '/' not in a.display and stat.S_ISSOCK((runtime/a.display).stat().st_mode)
env=dict(os.environ,XDG_RUNTIME_DIR=str(runtime),WAYLAND_DISPLAY=a.display,FLEX_GUI_BACKEND='wayland',COLLIE_HEADLESS='1')
env.pop('DISPLAY',None);env.pop('SDL_VIDEODRIVER',None);env.pop('SDL_VIDEO_DRIVER',None)
def run(name,args,child_env=None):
    r=subprocess.run([str(x) for x in args],env=env if child_env is None else child_env,cwd=ROOT,capture_output=True,timeout=30)
    (out/f'{name}.stderr.log').write_bytes(r.stderr)
    assert r.returncode==0,(name,r.returncode,r.stdout,r.stderr)
for scene in ['scroll','selection','stream','navigation']:
    request=out/f'{scene}.request.json';result=out/f'{scene}.result.json';capture=out/f'{scene}.rgba'
    request.write_text(json.dumps(dict(scene=scene,samples=24,output=str(result),capture=str(capture),native_feedback=a.native_feedback)))
    run(scene,[a.benchmark.resolve(),request]);row=json.loads(result.read_text())
    assert row['backend']=='wayland' and row['video_driver']=='wayland' and row['sdl_loaded'] is False,row
    assert len(row['cpu_work_ns'])==24 and row['counters'][7]==24,row
    assert capture.stat().st_size==row['pixel_width']*row['pixel_height']*4
    if a.native_feedback:
        assert row['presentation_feedback'] and len(row['presentation_records'])==24 and row['presented_updates']+row['discarded_updates']==24 and row['presented_updates']>0,row
        assert [r['tag'] for r in row['presentation_records']]==list(range(1,25)),row
        assert all(r['status'] in (1,2) and (r['status']==2 or r['presented_ns']>=r['submit_ns']>=r['origin_ns']) for r in row['presentation_records']),row
    if a.require_seat:assert row['native_seat'] and row['native_keyboard_keymap'] and row['native_keyboard_focus'],row
    print(f'PASS native Collie {scene}: replay/render/capture and process maps without SDL',flush=True)
if a.collie:
    # Check automatic selection and every documented override without opening
    # extra windows or starting the service. The full fixture below uses auto.
    auto={k:v for k,v in env.items() if k not in ['FLEX_GUI_BACKEND','SDL_VIDEODRIVER','SDL_VIDEO_DRIVER']}
    choices=[('auto',{},'wayland'),('explicit-native',{'FLEX_GUI_BACKEND':'wayland'},'wayland'),
             ('explicit-sdl',{'FLEX_GUI_BACKEND':'sdl2'},'sdl2'),
             ('sdl-driver',{'SDL_VIDEODRIVER':'dummy'},'sdl2'),
             ('native-override',{'FLEX_GUI_BACKEND':'wayland','SDL_VIDEODRIVER':'dummy'},'wayland')]
    selection=[]
    for label,overrides,expected in choices:
        r=subprocess.run([str(a.collie.resolve()),'--video-diagnostics'],env=dict(auto,**overrides),cwd=ROOT,capture_output=True,timeout=10)
        (out/('backend-'+label+'.log')).write_bytes(r.stdout+r.stderr)
        expected_driver='dummy' if label=='sdl-driver' else 'wayland'
        assert r.returncode==0 and ('Selected backend: '+expected_driver).encode() in r.stderr,(label,r.returncode,r.stderr)
        # Diagnostics must distinguish the GUI backend from its video driver.
        assert ('GUI backend: '+expected).encode() in r.stderr,(label,r.stderr)
        selection.append(dict(case=label,expected=expected,passed=True))
    r=subprocess.run([str(a.collie.resolve()),'--video-diagnostics'],env=dict(auto,FLEX_GUI_BACKEND='invalid'),cwd=ROOT,capture_output=True,timeout=10)
    assert r.returncode!=0 and b'Unknown GUI backend' in r.stderr,(r.returncode,r.stderr)
    selection.append(dict(case='invalid-override-rejected',passed=True))
    (out/'backend-selection.json').write_text(json.dumps(selection,indent=2)+'\n')
    # Preserve each fixture's inputs without restoring navigation from an earlier run.
    data=Path(tempfile.mkdtemp(prefix='data-',dir=out));session=data/'sessions/conversation-0';(session/'files').mkdir(parents=True,exist_ok=True)
    text='## Native Collie\n\nHäät and 中文, **Markdown**, `code` and a table.\n\n| Item | State |\n| --- | --- |\n| Native text | Ready |'
    messages=[dict(role='user',content='Hello'),dict(role='assistant',content=text)]
    (session/'session.json').write_text(json.dumps(dict(messages=messages,archive=messages,cards=[dict(kind='user',text='Hello'),dict(kind='assistant',text=text)])))
    (data/'settings.json').write_text(json.dumps(dict(current='conversation-0')))
    fixture=out/'fixture.json';fixture.write_text('[]')
    def event(at,request):return dict(at=at,request=request)
    narrow=row['width']<960
    settings_key='chat-menu' if narrow else 'desktop-settings'
    events=[event(100,dict(action='native_text',text='Häät 中文')),
            event(220,dict(action='event',event=dict(key=settings_key,action='menu',type='click'))),
            event(300,dict(action='event',event=dict(key='settings-nav-account',action='settings_section',action_id=2,type='click'))),
            event(450,dict(action='back')),
            event(600,dict(action='native_key',code=5,modifiers=64))]
    if narrow:
        events.append(event(750,dict(action='native_text',text='needle')))
        events.append(event(900,dict(action='back')))
    (out/'collie-fixture.json').write_text(json.dumps(dict(data=str(data),narrow=narrow,settings_key=settings_key),indent=2)+'\n')
    script=out/'events.json';script.write_text(json.dumps(events));state=out/'collie-state.json';capture=out/'collie.rgba';window=out/'collie-window.json'
    run('collie',[a.collie.resolve(),'--frames','90','--data',data,'--fixture',fixture,'--events',script,'--dump-state',state,'--dump-window',window,'--capture',capture],{k:v for k,v in env.items() if k not in ['FLEX_GUI_BACKEND','SDL_VIDEODRIVER','SDL_VIDEO_DRIVER']})
    result=json.loads(state.read_text());assert result['page']=='chat' and result['draft']=='Häät 中文' and result.get('sidebar_collapsed',0)==(0 if narrow else 1),result
    if narrow:assert result['query']=='needle','Compact Ctrl+B did not open and focus conversation search'
    display=json.loads(window.read_text());assert display['backend']=='wayland' and display['sdl_loaded'] is False,display
    assert (display['width'],display['height'])==(result['viewport_width'],result['viewport_height']),display
    assert capture.stat().st_size==display['pixel_width']*display['pixel_height']*4
    print('PASS full native Collie/service fixture: Unicode draft, settings/account, return, sidebar shortcut and capture',flush=True)
print('PASS native renderer scenes, backend selection and full Collie fixture; see separate input/lifecycle suites')
