#!/usr/bin/env python3
"""Native window lifecycle against independent state from private Weston 15.

No desktop sockets or package installs. GPU access and an extracted Weston root
are required. C/Python are test oracles/orchestration, never application code.
"""
import argparse,json,os,re,shlex,signal,struct,subprocess,tempfile,time,zlib
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--compiler',type=Path,required=True);p.add_argument('--weston-root',type=Path,required=True);p.add_argument('--ui-workflows',action='store_true',help='Run shared UI workflows instead of lifecycle checkpoints, on fresh private servers');p.add_argument('--out',type=Path,default=ROOT/'build/migration/window-session');a=p.parse_args()
out=a.out.resolve();out.mkdir(parents=True,exist_ok=True);package=a.weston_root.resolve()
flags=shlex.split(subprocess.check_output(['pkg-config','--cflags','wayland-server','pixman-1','xkbcommon'],text=True));module=out/'weston-window.so'
subprocess.run(['cc','-shared','-fPIC','-O2','-Wall','-Wextra','-Werror','-Wno-error=attributes','-I'+str(package/'usr/include/libweston-15'),*flags,'tests/ui/weston-window.c','-o',str(module)],cwd=ROOT,check=True)
def load(path):
    try:return json.loads(path.read_text())
    except (FileNotFoundError,json.JSONDecodeError):return None
def stop(proc):
    if proc is not None and proc.poll() is None:
        os.killpg(proc.pid,signal.SIGTERM)
        try:proc.wait(timeout=5)
        except subprocess.TimeoutExpired:os.killpg(proc.pid,signal.SIGKILL);proc.wait(timeout=5)
def png(path,w,h):
    raw=path.read_bytes();assert len(raw)==w*h*4
    def chunk(tag,data):return struct.pack('>I',len(data))+tag+data+struct.pack('>I',zlib.crc32(tag+data)&0xffffffff)
    rows=b''.join(b'\0'+raw[y*w*4:(y+1)*w*4] for y in range(h))
    path.with_suffix('.png').write_bytes(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',w,h,8,6,0,0,0))+chunk(b'IDAT',zlib.compress(rows))+chunk(b'IEND',b''))
reports=[]
for scale,pipeline in [(1,'ir'),(2,'direct')]:
    run=out/f'{scale}x-{pipeline}';run.mkdir(exist_ok=True);binary=run/'window-lifecycle';checkpoint=run/'checkpoint.json';server=run/'server.json';close=run/'request-close';ack=run/'ack';checkpoint.unlink(missing_ok=True);close.unlink(missing_ok=True)
    for path in run.glob('ack.*'):path.unlink()
    subprocess.run([str(a.compiler.resolve()),'--native-pipeline',pipeline,'tests/ui/wayland-window-lifecycle.flex','-o',str(binary)],cwd=ROOT,check=True)
    if a.ui_workflows:
        for scene in ['desktop','tables','scrolling','native-lifetime']:
            subprocess.run([str(a.compiler.resolve()),'--native-pipeline',pipeline,'tests/ui/'+scene+'.flex','-o',str(run/('ui-'+scene))],cwd=ROOT,check=True)
    helper=run/'idle-helper';helper.write_text('#!/usr/bin/python3\nimport os,time\nparent=os.getppid()\nwhile os.getppid()==parent: time.sleep(.1)\n');helper.chmod(0o755)
    config=run/'weston.ini';config.write_text('[core]\nxwayland=false\n[shell]\nclient='+str(package/'usr/lib/weston/weston-desktop-shell')+'\nlocking=false\nstartup-animation=none\nanimation=none\npanel-position=none\nbackground-type=solid\nbackground-color=0xff181818\n[input-method]\npath='+str(helper)+'\n')
    env=dict(os.environ)
    for key in ['DISPLAY','WAYLAND_DISPLAY','SWAYSOCK','HYPRLAND_INSTANCE_SIGNATURE','DBUS_SESSION_BUS_ADDRESS']:env.pop(key,None)
    env.update(LD_LIBRARY_PATH=str(package/'usr/lib')+':'+str(package/'usr/lib/weston'),WESTON_MODULE_MAP=';'.join(name+'='+str(package/'usr/lib/libweston-15'/name) for name in ['headless-backend.so','gl-renderer.so']),FLEX_WESTON_WINDOW_REPORT=str(server),FLEX_WESTON_WINDOW_CLOSE=str(close),FLEX_WESTON_UI_INPUT='1' if a.ui_workflows else '')
    app=None;observations=[]
    with tempfile.TemporaryDirectory(prefix='fs-window-') as runtime,(run/'weston.stderr.log').open('wb') as log,(run/'client.stdout.log').open('wb') as stdout,(run/'client.stderr.log').open('wb') as stderr:
        env.update(XDG_RUNTIME_DIR=runtime,WAYLAND_DISPLAY='fs-window-test')
        compositor=subprocess.Popen([str(package/'usr/bin/weston'),'--backend=headless-backend.so','--renderer=gl','--shell='+str(package/'usr/lib/weston/desktop-shell.so'),'--socket=fs-window-test','--width=1600','--height=1000','--scale='+str(scale),'--idle-time=0','--config='+str(config),'--fake-seat','--modules='+str(module),'--log='+str(run/'weston.log')],env=env,cwd=ROOT,stdout=log,stderr=log,start_new_session=True)
        try:
            until=time.monotonic()+10
            while not (Path(runtime)/env['WAYLAND_DISPLAY']).exists() and compositor.poll() is None and time.monotonic()<until:time.sleep(.02)
            assert compositor.poll() is None and (Path(runtime)/env['WAYLAND_DISPLAY']).exists(),'Private Weston startup failed; inspect logs'
            if a.ui_workflows:
                result=subprocess.run([str(run/'ui-desktop'),'--native',str(run)],cwd=ROOT,env=dict(env,FLEX_WESTON_UI_INPUT='1'),capture_output=True,timeout=90)
                (run/'ui-workflows.stdout.log').write_bytes(result.stdout);(run/'ui-workflows.stderr.log').write_bytes(result.stderr)
                assert result.returncode==0,('Native UI workflows failed',result.returncode,result.stderr.decode(errors='replace'))
                print(result.stdout.decode(),end='',flush=True)
                for scene in ['tables','scrolling','native-lifetime']:
                    result_scene=subprocess.run([str(run/('ui-'+scene)),'--native'],cwd=ROOT,env=env,capture_output=True,timeout=30)
                    (run/(scene+'.stdout.log')).write_bytes(result_scene.stdout);(run/(scene+'.stderr.log')).write_bytes(result_scene.stderr)
                    assert result_scene.returncode==0,(scene,result_scene.returncode,result_scene.stderr.decode(errors='replace'))
                    print(result_scene.stdout.decode(),end='',flush=True)
                reports.append(dict(scale=scale,pipeline=pipeline,ui_checks=int(re.search(rb'PASS: (\d+)',result.stdout)[1])))
            else:
                app=subprocess.Popen([str(binary),str(checkpoint),str(ack),str(run/'capture-'),str(run/'result.json')],cwd=ROOT,env=dict(env,WAYLAND_DEBUG='1'),stdout=stdout,stderr=stderr,start_new_session=True)
                for step in range(26):
                    until=time.monotonic()+10;client=None
                    while time.monotonic()<until and app.poll() is None:
                        client=load(checkpoint)
                        if client and client['step']==step:break
                        time.sleep(.01)
                    assert client and client['step']==step and app.poll() is None,('Client checkpoint failed',step,app.poll(),client)
                    assert client['xdg_version']==5,('Weston 15 xdg version negotiation differs',client)
                    until=time.monotonic()+4;state=None;okay=False
                    while time.monotonic()<until:
                        state=load(server)
                        if state:
                            if step==0:okay=not state['mapped'] and state['buffer_attaches']==0 and client['presents']==0
                            elif step==7:okay=not state['mapped']
                            elif step==10:okay=state['minimize_requests']==1 and (not state['listed'] or state['layer']==0)
                            else:
                                expected={1:(640,420),2:(800,500),4:(700,460),6:(700,460),9:(720,480),11:(720,480),12:(720,480),13:(720,480),14:(640,420),15:(800,500),17:(800,500),18:(800,500),**{i:(800,500) for i in range(19,25)},25:(640,420)}.get(step)
                                okay=state['mapped'] and (state['width'],state['height'])==(client['width'],client['height'])
                                opaque=step not in [19,20,22,24]
                                okay=okay and state['full_opaque']==opaque and state['opaque']==([0,0,client['width'],client['height']] if opaque else [0,0,0,0])
                                if expected:okay=okay and (client['width'],client['height'])==expected
                                if step in [3,8,16]:okay=okay and state['fullscreen'] and (client['width'],client['height'])==(1600,1000)
                                elif step==5:okay=okay and state['maximized'] and client['width']>=1500 and client['height']>=900
                                else:okay=okay and not state['fullscreen'] and not state['maximized']
                                title='Lifecycle 中文' if step<7 else 'Hidden title 中文' if step<14 else 'Fixed window' if step<25 else 'Disconnect fixture'
                                okay=okay and state['title']==title and state['app_id']=='org.flexscript.Collie'
                                # Weston 15's generic size getters return zero for
                                # xdg toplevels; keep those observations, and check
                                # independently logged protocol requests separately.
                                if step in [14,15,17,18] or 19<=step<25:okay=okay and (state['requested_min_width'],state['requested_min_height'],state['requested_max_width'],state['requested_max_height'])==(*expected,*expected)
                                else:okay=okay and all(state[k]==0 for k in ['requested_min_width','requested_min_height','requested_max_width','requested_max_height'])
                            if okay:break
                        time.sleep(.02)
                    observations.append(dict(client=client,server=state));(run/'observations.json').write_text(json.dumps(observations,indent=2)+'\n')
                    assert okay,('Compositor state differs',step,client,state)
                    if step==13:close.write_text('close')
                    if step==25:stop(compositor)
                    Path(str(ack)+'.'+str(step)).write_text('ack')
                app.wait(timeout=10);assert app.returncode==0,('Lifecycle app failed',app.returncode)
                result=load(run/'result.json');assert result and result['closes']==2 and result['rapid_remaps']==20 and result['gl_error']==0,result
                regions={};created=0
                for line in (run/'client.stderr.log').read_text().splitlines():
                    match=re.search(r'create_region\(new id wl_region#(\d+)\)',line)
                    if match:regions[match[1]]=regions.get(match[1],0)+1;created+=1
                    match=re.search(r'wl_region#(\d+)\.destroy\(',line)
                    if match:regions[match[1]]=regions.get(match[1],0)-1
                assert created and not any(regions.values()),('Temporary opaque region ownership differs',regions)
                (run/'opaque-ownership.json').write_text(json.dumps(dict(created=created,unreleased=0,opacity_transition_checks=6,checkpoints=26),indent=2)+'\n')
                for step in [1,8]:
                    client=observations[step]['client'];png(run/f'capture-{step}.rgba',client['pixel_width'],client['pixel_height'])
                reports.append(dict(scale=scale,pipeline=pipeline,**result))
        finally:stop(app);stop(compositor)
        assert compositor.returncode==0,('Private Weston shutdown failed',compositor.returncode)
    (run/'cleanup.json').write_text(json.dumps(dict(compositor_stopped=True,app_stopped=app is None or app.poll() is not None,runtime_removed=not Path(runtime).exists()))+'\n')
(out/'report.json').write_text(json.dumps(reports,indent=2)+'\n')
print('PASS private native desktop, tables and scrolling workflows at 1x IR / 2x direct' if a.ui_workflows else 'PASS private Weston 1x IR / 2x direct: hidden/map, resize, fullscreen/restore, maximize, minimize/remap, attributes, committed opaque/transparent/partial-frame regions, rapid remaps, close/disconnect and framebuffer pixels')
