#!/usr/bin/env python3
"""Independent pipe producer and real input for a private native GUI wait test."""
import argparse,json,os,signal,stat,subprocess,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--binary',type=Path,required=True);p.add_argument('--session',type=Path,required=True);p.add_argument('--out',type=Path,required=True);p.add_argument('--collie',type=Path);p.add_argument('--settings-key',choices=['desktop-settings','chat-menu'],default='desktop-settings');a=p.parse_args()
session=json.loads(a.session.read_text());runtime=Path(session['XDG_RUNTIME_DIR']);assert runtime.name.startswith('fs-ime-') and runtime.stat().st_uid==os.getuid() and stat.S_IMODE(runtime.stat().st_mode)==0o700
assert '/' not in session['WAYLAND_DISPLAY'] and stat.S_ISSOCK((runtime/session['WAYLAND_DISPLAY']).stat().st_mode)
env=dict(os.environ,**session);env.pop('DISPLAY',None);out=a.out.resolve();out.mkdir(parents=True,exist_ok=True);stage=out/'stage';stage.unlink(missing_ok=True);report=out/'report.json';input_r,input_w=os.pipe2(os.O_NONBLOCK|os.O_CLOEXEC);output_r,output_w=os.pipe2(os.O_NONBLOCK|os.O_CLOEXEC)
with (out/'client.stdout.log').open('wb') as stdout,(out/'client.stderr.log').open('wb') as stderr:
    app=subprocess.Popen([str(a.binary.resolve()),str(input_r),str(output_w),str(stage),str(report)],env=dict(env,WAYLAND_DEBUG='1'),cwd=ROOT,pass_fds=[input_r,output_w],stdout=stdout,stderr=stderr,start_new_session=True)
    os.close(input_r);os.close(output_w)
    try:
        sent=None
        for name in ['read','write','gui','hup']:
            until=time.monotonic()+6
            while time.monotonic()<until and app.poll() is None:
                if stage.exists() and stage.read_text()==name:break
                time.sleep(.01)
            assert app.poll() is None and stage.exists() and stage.read_text()==name,('Wait fixture readiness failed',name,app.poll())
            time.sleep(.1)
            if name=='read':sent=time.monotonic_ns();assert os.write(input_w,b'R')==1
            elif name=='write':assert os.read(output_r,8192)
            # Give a new virtual keyboard time to publish capabilities/keymap/focus.
            elif name=='gui':subprocess.run(['wtype','-s','200','-k','Escape','-s','50'],env=env,check=True,capture_output=True,timeout=3)
            else:os.close(input_w);input_w=-1
        app.wait(timeout=5);assert app.returncode==0,app.returncode
        row=json.loads(report.read_text());row['producer_to_observation_ns']=row['read_observed_ns']-sent
        assert row['backend']=='wayland' and row['gui_key'] and row['write_backpressure'] and row['hangup'] and row['invalid'],row
        # A generous functional bound detects a missed FD wake/full 5 s timeout.
        # This one sample does not establish p95 latency/performance acceptance.
        assert 0<=row['producer_to_observation_ns']<2_500_000_000,row
        report.write_text(json.dumps(row,indent=2)+'\n')
    finally:
        if app.poll() is None:os.killpg(app.pid,signal.SIGTERM);app.wait(timeout=5)
        if input_w>=0:os.close(input_w)
        os.close(output_r)
print('PASS native joint wait: independent delayed read/write readiness, real Escape input, hangup/invalid and caller-owned bytes')
if a.collie:
    fixture=out/'fixture.json';fixture.write_text('[]');data=out/'idle-data';data.mkdir(exist_ok=True)
    result=subprocess.run([str(a.collie.resolve()),'--hidden','--fixture',str(fixture),'--data',str(data),'--run-ms','1500','--dump-loop',str(out/'idle-loop.json')],env=dict(env,FLEX_GUI_BACKEND='wayland',COLLIE_HEADLESS='1'),cwd=ROOT,capture_output=True,timeout=15)
    (out/'collie-idle.stdout.log').write_bytes(result.stdout);(out/'collie-idle.stderr.log').write_bytes(result.stderr)
    assert result.returncode==0,(result.returncode,result.stdout,result.stderr)
    row=json.loads((out/'idle-loop.json').read_text());assert row['backend']=='wayland' and row['pidfd'] and row['presents']==0 and row['iterations']<40 and row['zero_waits']==0,row
    print('PASS native Collie hidden idle without frame-limited polling:',row)

    # Replay deadlines run through the ordinary native loop, without --frames.
    data=out/'replay-data';conversation=data/'sessions/conversation-0';(conversation/'files').mkdir(parents=True,exist_ok=True)
    messages=[dict(role='user',content='Deadline check'),dict(role='assistant',content='Keep the draft while visiting settings.')]
    (conversation/'session.json').write_text(json.dumps(dict(messages=messages,archive=messages,cards=[dict(kind=m['role'],text=m['content']) for m in messages])))
    (data/'settings.json').write_text(json.dumps(dict(current='conversation-0')))
    settings_key=a.settings_key
    events=[dict(at=100,request=dict(action='native_text',text='Häät 中文')),
            dict(at=220,request=dict(action='event',event=dict(key=settings_key,action='menu',type='click'))),
            dict(at=350,request=dict(action='event',event=dict(key='settings-nav-account',action='settings_section',action_id=2,type='click'))),
            dict(at=500,request=dict(action='back'))]
    script=out/'replay.json';script.write_text(json.dumps(events));state=out/'replay-state.json';window=out/'replay-window.json'
    result=subprocess.run([str(a.collie.resolve()),'--fixture',str(fixture),'--data',str(data),'--run-ms','2500','--events',str(script),'--dump-state',str(state),'--dump-window',str(window),'--dump-loop',str(out/'replay-loop.json')],env=dict(env,FLEX_GUI_BACKEND='wayland',COLLIE_HEADLESS='1'),cwd=ROOT,capture_output=True,timeout=15)
    (out/'collie-replay.stdout.log').write_bytes(result.stdout);(out/'collie-replay.stderr.log').write_bytes(result.stderr)
    assert result.returncode==0,(result.returncode,result.stdout,result.stderr)
    state=json.loads(state.read_text());window=json.loads(window.read_text());loop=json.loads((out/'replay-loop.json').read_text())
    assert state['page']=='chat' and state['draft']=='Häät 中文' and state['settings_section']=='account',state
    assert window['backend']=='wayland' and not window['sdl_loaded'] and loop['source_wakes']>0 and loop['iterations']<100,loop
    print('PASS ordinary native Collie loop: replay deadlines, Unicode draft, settings/account/return and bounded caret/service waits:',loop)

    # Terminate only the service belonging to this private Collie subprocess.
    # EOF/pidfd must wake the GUI even without input or a short UI deadline.
    exit_data=out/'exit-data';exit_data.mkdir(exist_ok=True)
    with (out/'collie-exit.stdout.log').open('wb') as stdout,(out/'collie-exit.stderr.log').open('wb') as stderr:
        app=subprocess.Popen([str(a.collie.resolve()),'--hidden','--fixture',str(fixture),'--data',str(exit_data),'--run-ms','10000','--dump-loop',str(out/'exit-loop.json')],env=dict(env,FLEX_GUI_BACKEND='wayland',COLLIE_HEADLESS='1'),cwd=ROOT,stdout=stdout,stderr=stderr,start_new_session=True)
        try:
            until=time.monotonic()+5;service=None
            while time.monotonic()<until and app.poll() is None:
                children=Path(f'/proc/{app.pid}/task/{app.pid}/children').read_text().split()
                for candidate in children:
                    executable=Path(f'/proc/{candidate}/exe')
                    try:matches=executable.resolve().name=='service-native'
                    except FileNotFoundError:matches=False
                    if matches:service=int(candidate);break
                if service:break
                time.sleep(.01)
            assert service is not None,'Private service did not start'
            time.sleep(.3);before=time.monotonic_ns();os.kill(service,signal.SIGTERM);code=app.wait(timeout=3);elapsed=time.monotonic_ns()-before
            assert code==1,('Lost service was not reported as failure',code)
            (out/'exit-observation.json').write_text(json.dumps(dict(returncode=code,signal_to_exit_ns=elapsed),indent=2)+'\n')
        finally:
            if app.poll() is None:os.killpg(app.pid,signal.SIGTERM);app.wait(timeout=5)
    print('PASS native Collie: service termination wakes the blocked GUI and exits with failure')
