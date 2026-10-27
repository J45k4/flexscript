#!/usr/bin/env python3
"""Drive real Fcitx Pinyin on an explicitly private headless compositor.

Requires a separate runtime, D-Bus session, profile with Pinyin and running
Fcitx. No default compositor/session is ever selected. No system configuration
is modified. The session JSON must name those private environment values.
"""
import argparse,json,os,re,shutil,stat,struct,subprocess,tempfile,time,zlib
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--binary',type=Path,required=True);p.add_argument('--session',type=Path,required=True)
p.add_argument('--out',type=Path,default=ROOT/'build/migration/ime-tests')
p.add_argument('--expect-scale',type=int);p.add_argument('--collie',type=Path)
a=p.parse_args();out=a.out.resolve();out.mkdir(parents=True,exist_ok=True)
session=json.loads(a.session.read_text());runtime=Path(session['XDG_RUNTIME_DIR'])
assert runtime.stat().st_uid==os.getuid() and stat.S_IMODE(runtime.stat().st_mode)==0o700
assert session['DBUS_SESSION_BUS_ADDRESS'] and session['WAYLAND_DISPLAY']
assert '/' not in session['WAYLAND_DISPLAY'] and stat.S_ISSOCK((runtime/session['WAYLAND_DISPLAY']).stat().st_mode)
desktop=os.environ.get('FLEX_IME_DESKTOP_RUNTIME',os.environ.get('XDG_RUNTIME_DIR',f'/run/user/{os.getuid()}'))
assert runtime!=Path(desktop) and runtime!=Path(f'/run/user/{os.getuid()}'),'Refusing the desktop runtime'
env=dict(os.environ,**session);env.pop('DISPLAY',None);env.pop('HYPRLAND_INSTANCE_SIGNATURE',None)
prefix=out/'test-';ready=out/'test-ready';ready.unlink(missing_ok=True)
def control(*args):return subprocess.run(args,env=env,check=True,capture_output=True,text=True,timeout=10).stdout
def activate_pinyin(label):
    # A newly focused Wayland input context can replace the context selected
    # just before its focus notification. Wait for the private service to
    # acknowledge both the active state and method, instead of a fixed sleep.
    observations=[];stable=0;until=time.monotonic()+8
    while time.monotonic()<until:
        control('fcitx5-remote','-o');control('fcitx5-remote','-s','pinyin');time.sleep(.1)
        method=control('fcitx5-remote','-n').strip();state=control('fcitx5-remote').strip()
        observations.append(dict(method=method,state=state));stable=stable+1 if method=='pinyin' and state=='2' else 0
        if stable>=2:
            (out/(label+'-activation.json')).write_text(json.dumps(observations,indent=2)+'\n');return
    (out/(label+'-activation.json')).write_text(json.dumps(observations,indent=2)+'\n')
    raise AssertionError('Private Fcitx did not activate Pinyin: '+repr(observations))
def png(path,width,height):
    raw=path.read_bytes();assert len(raw)==width*height*4
    def chunk(tag,data):return struct.pack('>I',len(data))+tag+data+struct.pack('>I',zlib.crc32(tag+data)&0xffffffff)
    scan=b''.join(b'\0'+raw[y*width*4:(y+1)*width*4] for y in range(height))
    path.with_suffix('.png').write_bytes(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',width,height,8,6,0,0,0))+chunk(b'IDAT',zlib.compress(scan))+chunk(b'IEND',b''))
with (out/'client.stdout.log').open('w') as stdout,(out/'client.stderr.log').open('w') as stderr:
    client=subprocess.Popen([str(a.binary.resolve()),str(prefix)],env=dict(env,WAYLAND_DEBUG='1'),stdout=stdout,stderr=stderr,cwd=ROOT)
    try:
        for _ in range(250):
            if ready.exists() or client.poll() is not None:break
            time.sleep(.02)
        assert ready.exists(),'Native IME fixture did not become ready'
        activate_pinyin('fixture')
        control('wtype','-d','100','nihao')
        # Keep the actual IME candidate popup visible for an independent capture.
        time.sleep(.3)
        if shutil.which('grim'):
            control('grim',str(out/'compositor-preedit.png'))
        control('wtype','-k','space')
        assert client.wait(timeout=35)==0,'Native IME fixture failed; inspect client logs'
    finally:
        if client.poll() is None:client.terminate();client.wait(timeout=5)
report=json.loads((out/'test-report.json').read_text())
assert report['value']=='你好' and report['saw_preedit'] and report['manager'],report
assert not report['sdl_loaded'] and report['gl_error']==0,report
if a.expect_scale:assert report['scale']==a.expect_scale,report
assert any(r['preedit'] for r in report['transactions']) and any(r['commit']=='你好' for r in report['transactions']),report
assert report['caret_x']>0 and report['caret_y']>0 and report['caret_height']>1,report
for name in ['preedit','commit']:png(out/f'test-{name}.rgba',report['width'],report['height'])
print('PASS real Fcitx Pinyin: preedit, Chinese commit, native editor, caret rectangle, zero GL errors and no SDL')
if a.collie:
    data=Path(tempfile.mkdtemp(prefix='collie-data-',dir=out));conversation=data/'sessions/conversation-0';(conversation/'files').mkdir(parents=True,exist_ok=True)
    (out/'collie-fixture.json').write_text(json.dumps(dict(data=str(data)),indent=2)+'\n')
    messages=[dict(role='user',content='Native IME check'),dict(role='assistant',content='Type a Chinese draft in the composer.')]
    (conversation/'session.json').write_text(json.dumps(dict(messages=messages,archive=messages,cards=[dict(kind=m['role'],text=m['content']) for m in messages])))
    (data/'settings.json').write_text(json.dumps(dict(current='conversation-0')))
    fixture=out/'fixture.json';fixture.write_text('[]');state=out/'collie-state.json';display=out/'collie-window.json';capture=out/'collie.rgba'
    log=out/'collie.stderr.log'
    with log.open('w') as stderr,(out/'collie.stdout.log').open('w') as stdout:
        child=subprocess.Popen([str(a.collie.resolve()),'--run-ms','6400','--dump-loop',str(out/'collie-loop.json'),'--data',str(data),'--fixture',str(fixture),'--dump-state',str(state),'--dump-window',str(display),'--capture',str(capture)],env=dict({k:v for k,v in env.items() if k not in ['FLEX_GUI_BACKEND','SDL_VIDEODRIVER','SDL_VIDEO_DRIVER']},WAYLAND_DEBUG='1',COLLIE_HEADLESS='1'),cwd=ROOT,stdout=stdout,stderr=stderr)
        try:
            until=time.monotonic()+10
            while time.monotonic()<until and child.poll() is None:
                if re.search(r'zwp_text_input_v3#\d+\.set_cursor_rectangle\(',log.read_text(errors='replace')):break
                time.sleep(.02)
            assert child.poll() is None,'Full Collie did not open its composer'
            activate_pinyin('collie')
            control('wtype','-d','100','nihao');time.sleep(.3)
            if shutil.which('grim'):control('grim',str(out/'collie-compositor-preedit.png'))
            control('wtype','-k','space')
            assert child.wait(timeout=25)==0,'Full Collie failed; inspect collie logs'
        finally:
            if child.poll() is None:child.terminate();child.wait(timeout=5)
    value=json.loads(state.read_text());window=json.loads(display.read_text());wire=log.read_text()
    assert value['page']=='chat' and value['draft']=='你好',value
    loop=json.loads((out/'collie-loop.json').read_text());assert loop['backend']=='wayland' and loop['pidfd'] and loop['source_wakes']>0 and loop['iterations']<160,loop
    assert window['backend']=='wayland' and not window['sdl_loaded'],window
    assert 'preedit_string("ni hao"' in wire and 'commit_string("你好")' in wire
    if a.expect_scale:assert window['scale']==a.expect_scale,window
    png(capture,window['pixel_width'],window['pixel_height'])
    print('PASS full native Collie/service: real Pinyin preedit, Chinese draft, composer candidate popup, event-driven waits and clean shutdown')
