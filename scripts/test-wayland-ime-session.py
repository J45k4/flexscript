#!/usr/bin/env python3
"""Create and remove a private headless Sway/Fcitx session for the IME suite.

This is test orchestration only. Requires Sway, Fcitx with Pinyin, wtype, a render
node and dbus-run-session. --package-root supports dependencies extracted into
ignored build output, without installing or changing system configuration.
"""
import argparse,json,os,signal,struct,subprocess,sys,tempfile,time,zlib
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def text_capture_png(path,width,height):
    raw=path.read_bytes();assert len(raw)==width*height*4
    def chunk(tag,data):return struct.pack('>I',len(data))+tag+data+struct.pack('>I',zlib.crc32(tag+data)&0xffffffff)
    scan=b''.join(b'\0'+raw[y*width*4:(y+1)*width*4] for y in range(height))
    path.with_suffix('.png').write_bytes(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',width,height,8,6,0,0,0))+chunk(b'IDAT',zlib.compress(scan))+chunk(b'IEND',b''))
def runtime_mounts(runtime):
    return [(fields[4],fields[fields.index('-')+1]) for line in Path('/proc/self/mountinfo').read_text().splitlines()
            if (fields:=line.split())[4].startswith(runtime+'/')]
def finish_runtime(runtime,out):
    # D-Bus activated document portals can finish after Sway/dbus-run-session.
    # Wait for their private FUSE mount before TemporaryDirectory traverses it.
    initial=runtime_mounts(runtime);until=time.monotonic()+3
    while runtime_mounts(runtime) and time.monotonic()<until:time.sleep(.05)
    unmounted=[]
    for path,kind in runtime_mounts(runtime):
        assert path==runtime+'/doc' and kind=='fuse.portal',('Unexpected private-runtime mount',path,kind)
        root=Path(runtime);assert root.name.startswith('fs-ime-') and root.parent==Path(tempfile.gettempdir()) and root.stat().st_uid==os.getuid()
        result=subprocess.run(['fusermount3','-u',path],capture_output=True,text=True,timeout=3)
        unmounted.append(dict(path=path,returncode=result.returncode,stderr=result.stderr))
        assert result.returncode==0,('Could not unmount private test portal',unmounted)
    remaining=runtime_mounts(runtime)
    (out/'runtime-cleanup.json').write_text(json.dumps(dict(initial=initial,unmounted=unmounted,remaining=remaining),indent=2)+'\n')
    assert not remaining,('Private test mount survived shutdown',remaining)
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--binary',type=Path,required=True);p.add_argument('--collie',type=Path)
p.add_argument('--text-fixture',type=Path)
p.add_argument('--window-fixture',type=Path)
p.add_argument('--weighted-fixture',type=Path)
p.add_argument('--gpu-timing-fixture',type=Path,action='append',default=[])
p.add_argument('--renderer-state-fixture',type=Path,action='append',default=[])
p.add_argument('--font-sizing-fixture',type=Path,action='append',default=[])
p.add_argument('--egl-config-fixture',type=Path,action='append',default=[])
p.add_argument('--canvas-clear-fixture',type=Path,action='append',default=[])
p.add_argument('--measure-reuse-fixture',type=Path,action='append',default=[])
p.add_argument('--model-copy-fixture',type=Path,action='append',default=[])
p.add_argument('--wait-fixture',type=Path)
p.add_argument('--presentation-fixture',type=Path)
p.add_argument('--sdl-presentation-fixture',type=Path)
p.add_argument('--paired-benchmark',type=Path)
p.add_argument('--typing-protocol-trace',type=Path,help='Run short diagnostic typing traces with this benchmark; not performance evidence')
p.add_argument('--native-submit-control',type=Path,help='Compare this frozen native baseline against --paired-benchmark without GPU queries')
p.add_argument('--native-control-contexts',nargs=2,help='Require actual GL versions and matching buffer settings in the native A/B comparison')
p.add_argument('--native-control-scenes',nargs='+',choices=['scroll','selection','stream','navigation','typing'])
p.add_argument('--native-measure-reuse-control',action='store_true')
p.add_argument('--native-direct-copy-control',action='store_true')
p.add_argument('--paired-performance',action='store_true')
p.add_argument('--paired-typing',action='store_true',help='Also run matched Unicode typing correctness and seven paired latency runs')
p.add_argument('--paired-arrival-ms',type=int,default=0,help='Also measure scroll/selection/typing arrivals on a fixed 1..1000 ms schedule')
p.add_argument('--paired-gpu',action='store_true',help='Also run all five workloads with diagnostic GPU timestamp queries')
p.add_argument('--paired-gpu-present',action='store_true',help='Also profile draw and successful present GPU intervals with a final glFlush; implies --paired-gpu')
p.add_argument('--idle-focus',type=Path,help='Run matched full-Collie idle/caret checks with this private focus fixture')
p.add_argument('--idle-seconds',type=int,default=60)
p.add_argument('--idle-runs',type=int,default=1)
p.add_argument('--benchmark',type=Path)
p.add_argument('--benchmark-feedback',action='store_true')
p.add_argument('--package-root',type=Path);p.add_argument('--sway',type=Path)
p.add_argument('--render-node',type=Path,default=Path('/dev/dri/renderD128'))
p.add_argument('--scale',type=int,default=1250);p.add_argument('--out',type=Path,default=ROOT/'build/migration/ime-headless-tests')
a=p.parse_args();out=a.out.resolve();out.mkdir(parents=True,exist_ok=True)
if a.paired_gpu_present:a.paired_gpu=True
assert 1000<=a.scale<=4000 and a.render_node.exists() and 0<=a.paired_arrival_ms<=1000
assert not (a.paired_arrival_ms or a.paired_typing or a.paired_performance or a.paired_gpu) or a.paired_benchmark,'Paired measurements need --paired-benchmark'
assert not a.native_submit_control or a.paired_benchmark,'Native control needs the candidate --paired-benchmark'
assert not a.native_control_contexts or a.native_submit_control,'Context control versions need --native-submit-control'
assert not (a.native_control_scenes or a.native_measure_reuse_control or a.native_direct_copy_control) or a.native_submit_control,'Native control options need --native-submit-control'
assert not a.idle_focus or (a.collie and 2<=a.idle_seconds<=600 and 1<=a.idle_runs<=7),'Idle checks need Collie, 2..600 seconds and 1..7 runs'
env=dict(os.environ)
env['FLEX_IME_DESKTOP_RUNTIME']=os.environ.get('XDG_RUNTIME_DIR',f'/run/user/{os.getuid()}')
for key in ['DISPLAY','WAYLAND_DISPLAY','SWAYSOCK','HYPRLAND_INSTANCE_SIGNATURE','DBUS_SESSION_BUS_ADDRESS','DBUS_SESSION_BUS_PID','DBUS_SESSION_BUS_WINDOWID','SESSION_MANAGER']:
    env.pop(key,None)
for name in ['config','data','state','cache']:
    directory=out/name;directory.mkdir(exist_ok=True);env['XDG_'+name.upper()+'_HOME']=str(directory)
env.update(WLR_BACKENDS='headless',WLR_LIBINPUT_NO_DEVICES='1',WLR_RENDERER='gles2',WLR_RENDER_DRM_DEVICE=str(a.render_node.resolve()),XDG_CURRENT_DESKTOP='sway')
package=a.package_root.resolve() if a.package_root else None
if package:
    env['LD_LIBRARY_PATH']=str(package/'usr/lib')
    env['XDG_DATA_DIRS']=str(package/'usr/share')+':/usr/share'
    env['FCITX_ADDON_DIRS']=str(package/'usr/lib/fcitx5')+':/usr/lib/fcitx5'
    env['FCITX_DATA_DIRS']=str(package/'usr/share/fcitx5')+':/usr/share/fcitx5'
    env['LIBIME_MODEL_DIRS']=str(package/'usr/share/libime')
sway=a.sway.resolve() if a.sway else package/'usr/bin/sway' if package else Path('/usr/bin/sway')
profile=out/'config/fcitx5/profile';profile.parent.mkdir(exist_ok=True)
profile.write_text('[Groups/0]\nName=Default\nDefault Layout=us\nDefaultIM=pinyin\n\n[Groups/0/Items/0]\nName=keyboard-us\nLayout=\n\n[Groups/0/Items/1]\nName=pinyin\nLayout=\n\n[GroupOrder]\n0=Default\n')
session=out/'session.json';session.unlink(missing_ok=True)
helper=out/'start-input-method.py'
helper.write_text('''import json,os
from pathlib import Path
base=Path(__file__).resolve().parent
keys=['XDG_RUNTIME_DIR','WAYLAND_DISPLAY','SWAYSOCK','DBUS_SESSION_BUS_ADDRESS','XDG_CONFIG_HOME','XDG_DATA_HOME','XDG_STATE_HOME','XDG_CACHE_HOME','XDG_DATA_DIRS','LD_LIBRARY_PATH']
(base/'session.json').write_text(json.dumps({k:os.environ[k] for k in keys if k in os.environ}))
log=os.open(str(base/'fcitx.log'),os.O_WRONLY|os.O_CREAT|os.O_TRUNC,0o600);os.dup2(log,1);os.dup2(log,2);os.close(log)
os.execvp('fcitx5',['fcitx5','-D','--disable','all','--enable','wayland,waylandim,dbus,dbusfrontend,keyboard,pinyin,punctuation,classicui','--verbose','key_trace=5'])
''')
config=out/'sway.conf'
config.write_text('xwayland disable\noutput HEADLESS-1 mode 1600x1000@60Hz scale '+str(a.scale/1000)+'\nseat seat0 fallback true\ninput * xkb_layout us\ndefault_border none\ngaps inner 0\ngaps outer 0\nfocus_follows_mouse no\nexec /usr/bin/python3 "'+str(helper)+'"\n')
with tempfile.TemporaryDirectory(prefix='fs-ime-') as runtime,(out/'sway.log').open('w') as log:
    env['XDG_RUNTIME_DIR']=runtime
    compositor=subprocess.Popen(['dbus-run-session','--',str(sway),'--unsupported-gpu','--config',str(config),'--debug'],env=env,stdout=log,stderr=log,start_new_session=True,cwd=ROOT)
    keyboard=None
    try:
        until=time.monotonic()+10
        while not session.exists() and compositor.poll() is None and time.monotonic()<until:time.sleep(.02)
        assert session.exists() and compositor.poll() is None,'Private compositor failed; inspect sway.log'
        private=dict(env,**json.loads(session.read_text()))
        until=time.monotonic()+5
        while time.monotonic()<until:
            probe=subprocess.run(['fcitx5-remote','-n'],env=private,capture_output=True,text=True,timeout=1)
            if probe.returncode==0 and probe.stdout.strip():break
            time.sleep(.05)
        command=[sys.executable,str(ROOT/'scripts/test-wayland-ime.py'),'--binary',str(a.binary.resolve()),'--session',str(session),'--expect-scale',str(a.scale),'--out',str(out/'results')]
        if a.collie:command+=['--collie',str(a.collie.resolve())]
        subprocess.run(command,check=True,env=env,cwd=ROOT,timeout=90)
        if a.paired_benchmark or a.typing_protocol_trace:
            # A text-input enter without any keyboard gives the native adapter
            # focus, while SDL needs a real keyboard enter to activate its IME.
            # Keep one idle virtual device for BOTH variants and all paired runs.
            keyboard_log=(out/'keyboard.log').open('wb')
            try:keyboard=subprocess.Popen(['wtype','-s','3600000'],env=private,cwd=ROOT,stdout=keyboard_log,stderr=keyboard_log,start_new_session=True)
            finally:keyboard_log.close()
            time.sleep(.15);assert keyboard.poll() is None,'Persistent private keyboard did not start'
            swaymsg=package/'usr/bin/swaymsg' if package else Path('/usr/bin/swaymsg')
            devices=json.loads(subprocess.check_output([str(swaymsg),'-r','-t','get_inputs'],env=private,cwd=ROOT,text=True,timeout=5))
            assert any(device['type']=='keyboard' for device in devices),'Private session has no keyboard device'
            (out/'keyboard.json').write_text(json.dumps(dict(pid=keyboard.pid,devices=devices),indent=2)+'\n')
        if a.typing_protocol_trace:
            command=[sys.executable,str(ROOT/'scripts/test-typing-protocol.py'),'--benchmark',str(a.typing_protocol_trace.resolve()),'--session',str(session),'--out',str(out/'typing-protocol')]
            subprocess.run(command,check=True,env=private,cwd=ROOT,timeout=120)
        if a.model_copy_fixture:
            command=[sys.executable,str(ROOT/'scripts/test-model-copy.py'),'--session',str(session),'--out',str(out/'model-copy')]
            for binary in a.model_copy_fixture:command+=['--binary',str(binary.resolve())]
            subprocess.run(command,check=True,env=private,cwd=ROOT,timeout=200)
        if a.measure_reuse_fixture:
            command=[sys.executable,str(ROOT/'scripts/test-measure-reuse.py'),'--session',str(session),'--out',str(out/'measure-reuse')]
            for binary in a.measure_reuse_fixture:command+=['--binary',str(binary.resolve())]
            subprocess.run(command,check=True,env=private,cwd=ROOT,timeout=180)
        if a.canvas_clear_fixture:
            command=[sys.executable,str(ROOT/'scripts/test-canvas-clear.py'),'--session',str(session),'--out',str(out/'canvas-clear')]
            for binary in a.canvas_clear_fixture:command+=['--binary',str(binary.resolve())]
            subprocess.run(command,check=True,env=private,cwd=ROOT,timeout=300)
        if a.egl_config_fixture:
            command=[sys.executable,str(ROOT/'scripts/test-egl-config.py'),'--session',str(session),'--out',str(out/'egl-config')]
            for binary in a.egl_config_fixture:command+=['--binary',str(binary.resolve())]
            subprocess.run(command,check=True,env=private,cwd=ROOT,timeout=120)
        if a.font_sizing_fixture:
            command=[sys.executable,str(ROOT/'scripts/test-font-sizing.py'),'--session',str(session),'--out',str(out/'font-sizing')]
            for binary in a.font_sizing_fixture:command+=['--binary',str(binary.resolve())]
            subprocess.run(command,check=True,env=private,cwd=ROOT,timeout=120)
        if a.idle_focus:
            command=[sys.executable,str(ROOT/'scripts/test-collie-idle.py'),'--collie',str(a.collie.resolve()),'--focus',str(a.idle_focus.resolve()),'--session',str(session),'--swaymsg',str(package/'usr/bin/swaymsg') if package else '/usr/bin/swaymsg','--seconds',str(a.idle_seconds),'--runs',str(a.idle_runs),'--out',str(out/'idle')]
            subprocess.run(command,check=True,env=private,cwd=ROOT,timeout=(a.idle_seconds+20)*4*a.idle_runs+60)
        if a.text_fixture:
            result=subprocess.run([str(a.text_fixture.resolve()),'--native',str(out/'results/text-editing-')],env=private,cwd=ROOT,capture_output=True,text=True,timeout=30)
            (out/'results/text-editing.stderr.log').write_text(result.stderr)
            (out/'results/text-editing.stdout.log').write_text(result.stdout)
            assert result.returncode==0,'Native text fixture failed; inspect text-editing.stderr.log'
            facts=json.loads(result.stdout);assert facts['backend']=='wayland' and facts['scale']==a.scale and facts['gl_error']==0,facts
            text_capture_png(out/'results/text-editing-capture.rgba',facts['width'],facts['height'])
            print('PASS native retained Unicode editor:',facts,flush=True)
        if a.weighted_fixture:
            result=subprocess.run([str(a.weighted_fixture.resolve())],env=dict(private,FLEX_GUI_BACKEND='wayland'),cwd=ROOT,capture_output=True,text=True,timeout=20)
            (out/'results/weighted-layout.stdout.log').write_text(result.stdout);(out/'results/weighted-layout.stderr.log').write_text(result.stderr)
            assert result.returncode==0,('Native weighted layout failed',result.stdout,result.stderr)
            print('PASS native weighted layout: odd/even widths, unchanged pixels and zero redundant text/texture work',flush=True)
        for index,binary in enumerate(a.gpu_timing_fixture):
            command=[sys.executable,str(ROOT/'scripts/test-gpu-timing.py'),'--binary',str(binary.resolve()),'--session',str(session),'--out',str(out/f'gpu-timing-{index}')]
            subprocess.run(command,check=True,env=private,cwd=ROOT,timeout=60)
        for index,binary in enumerate(a.renderer_state_fixture):
            command=[sys.executable,str(ROOT/'scripts/test-renderer-state.py'),'--binary',str(binary.resolve()),'--session',str(session),'--out',str(out/f'renderer-state-{index}')]
            subprocess.run(command,check=True,env=private,cwd=ROOT,timeout=30)
        if a.window_fixture:
            command=[sys.executable,str(ROOT/'scripts/test-wayland-window-size.py'),'--binary',str(a.window_fixture.resolve()),'--session',str(session),'--swaymsg',str(package/'usr/bin/swaymsg') if package else '/usr/bin/swaymsg','--out',str(out/'window-size')]
            subprocess.run(command,check=True,env=private,cwd=ROOT,timeout=90)
        if a.paired_benchmark:
            command=[sys.executable,str(ROOT/'scripts/test-presentation-pair.py'),'--benchmark',str(a.paired_benchmark.resolve()),'--session',str(session),'--out',str(out/'paired-smoke')]
            subprocess.run(command,check=True,env=private,cwd=ROOT,timeout=250)
            if a.native_submit_control:
                command=[sys.executable,str(ROOT/'scripts/compare-native-submission.py'),'--before',str(a.native_submit_control.resolve()),'--after',str(a.paired_benchmark.resolve()),'--session',str(session),'--out',str(out/'native-submission-control')]
                if a.native_control_contexts:command+=['--context-versions',*a.native_control_contexts]
                if a.native_control_scenes:command+=['--scenes',*a.native_control_scenes]
                if a.native_measure_reuse_control:command+=['--measure-reuse-control']
                if a.native_direct_copy_control:command+=['--direct-copy-control']
                subprocess.run(command,check=True,env=private,cwd=ROOT,timeout=1000)
            if a.paired_performance:
                command=[sys.executable,str(ROOT/'scripts/benchmark-ui.py'),'--baseline',str(a.paired_benchmark.resolve()),'--candidate',str(a.paired_benchmark.resolve()),'--presentation-feedback','--out',str(out/'paired-performance')]
                subprocess.run(command,check=True,env=private,cwd=ROOT,timeout=1500)
            if a.paired_typing:
                command=[sys.executable,str(ROOT/'scripts/test-presentation-pair.py'),'--benchmark',str(a.paired_benchmark.resolve()),'--session',str(session),'--scenes','typing','--out',str(out/'typing-smoke')]
                subprocess.run(command,check=True,env=private,cwd=ROOT,timeout=90)
                command=[sys.executable,str(ROOT/'scripts/benchmark-ui.py'),'--baseline',str(a.paired_benchmark.resolve()),'--candidate',str(a.paired_benchmark.resolve()),'--presentation-feedback','--scenes','typing','--out',str(out/'typing-performance')]
                subprocess.run(command,check=True,env=private,cwd=ROOT,timeout=600)
            if a.paired_arrival_ms:
                common=['--scenes','scroll','selection','typing','--replay-interval-ms',str(a.paired_arrival_ms)]
                command=[sys.executable,str(ROOT/'scripts/test-presentation-pair.py'),'--benchmark',str(a.paired_benchmark.resolve()),'--session',str(session),*common,'--out',str(out/'arrival-smoke')]
                subprocess.run(command,check=True,env=private,cwd=ROOT,timeout=150)
                command=[sys.executable,str(ROOT/'scripts/benchmark-ui.py'),'--baseline',str(a.paired_benchmark.resolve()),'--candidate',str(a.paired_benchmark.resolve()),'--presentation-feedback',*common,'--out',str(out/'arrival-performance')]
                subprocess.run(command,check=True,env=private,cwd=ROOT,timeout=1500)
            if a.paired_gpu:
                common=['--gpu-present-timing' if a.paired_gpu_present else '--gpu-timing','--scenes','scroll','selection','stream','navigation','typing','--replay-interval-ms','23']
                command=[sys.executable,str(ROOT/'scripts/test-presentation-pair.py'),'--benchmark',str(a.paired_benchmark.resolve()),'--session',str(session),*common,'--out',str(out/'gpu-smoke')]
                subprocess.run(command,check=True,env=private,cwd=ROOT,timeout=250)
                command=[sys.executable,str(ROOT/'scripts/benchmark-ui.py'),'--baseline',str(a.paired_benchmark.resolve()),'--candidate',str(a.paired_benchmark.resolve()),'--presentation-feedback',*common,'--out',str(out/'gpu-performance')]
                subprocess.run(command,check=True,env=private,cwd=ROOT,timeout=1500)
        if a.sdl_presentation_fixture:
            command=[sys.executable,str(ROOT/'scripts/test-sdl-presentation.py'),'--binary',str(a.sdl_presentation_fixture.resolve()),'--session',str(session),'--out',str(out/'sdl-presentation')]
            subprocess.run(command,check=True,env=private,cwd=ROOT,timeout=45)
        if a.presentation_fixture:
            command=[sys.executable,str(ROOT/'scripts/test-wayland-presentation.py'),'--binary',str(a.presentation_fixture.resolve()),'--session',str(session),'--out',str(out/'presentation')]
            subprocess.run(command,check=True,env=private,cwd=ROOT,timeout=30)
        if a.wait_fixture:
            command=[sys.executable,str(ROOT/'scripts/test-wayland-wait.py'),'--binary',str(a.wait_fixture.resolve()),'--session',str(session),'--out',str(out/'wait')]
            if a.collie:command+=['--collie',str(a.collie.resolve()),'--settings-key','chat-menu' if 1_600_000/a.scale<960 else 'desktop-settings']
            subprocess.run(command,check=True,env=private,cwd=ROOT,timeout=90)
        if a.benchmark:
            command=[sys.executable,str(ROOT/'scripts/test-wayland-ui.py'),'--benchmark',str(a.benchmark.resolve()),'--runtime',runtime,'--display',private['WAYLAND_DISPLAY'],'--out',str(out/'ui-smoke')]
            if a.collie:command+=['--collie',str(a.collie.resolve())]
            if a.benchmark_feedback:command+=['--native-feedback']
            subprocess.run(command,check=True,env=private,cwd=ROOT,timeout=150)
    finally:
        if keyboard is not None:
            if keyboard.poll() is None:
                os.killpg(keyboard.pid,signal.SIGTERM)
                try:keyboard.wait(timeout=5)
                except subprocess.TimeoutExpired:os.killpg(keyboard.pid,signal.SIGKILL);keyboard.wait(timeout=5)
            (out/'keyboard-cleanup.json').write_text(json.dumps(dict(pid=keyboard.pid,stopped=keyboard.poll() is not None,returncode=keyboard.returncode))+'\n')
        # The process group belongs exclusively to this test's D-Bus/Sway.
        if compositor.poll() is None:
            os.killpg(compositor.pid,signal.SIGTERM)
            try:compositor.wait(timeout=5)
            except subprocess.TimeoutExpired:os.killpg(compositor.pid,signal.SIGKILL);compositor.wait(timeout=5)
        finish_runtime(runtime,out)
print('Private headless compositor stopped; artifacts:',out)
