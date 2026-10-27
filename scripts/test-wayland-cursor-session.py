#!/usr/bin/env python3
"""Animated cursor and seat lifecycle on a fresh private headless Weston.

Requires an already extracted Weston 15 root and GPU access. No package installs,
desktop sockets or system configuration. C code is a test-only protocol producer.
"""
import argparse,json,os,re,shlex,signal,struct,subprocess,tempfile,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--compiler',type=Path,required=True)
p.add_argument('--weston-root',type=Path,required=True)
p.add_argument('--out',type=Path,default=ROOT/'build/migration/cursor-session')
p.add_argument('--regressions',action='store_true',help='Also check scale/shape/input and independent clipboard peers on a fresh server')
a=p.parse_args();out=a.out.resolve();out.mkdir(parents=True,exist_ok=True);package=a.weston_root.resolve()

def cursor_file(path,animated):
    chunks=[];toc=[];offset=16+12*(12 if animated else 4)
    for scale in range(1,5):
        frames=[(24,24,2,3,45),(32,20,8,4,70),(20,32,4,10,115)] if animated else [(24,24,12,12,0)]
        for frame,(width,height,hx,hy,delay) in enumerate(frames):
            width*=scale;height*=scale;hx*=scale;hy*=scale
            header=struct.pack('<9I',36,0xfffd0002,24*scale,1,width,height,hx,hy,delay)
            color=[0xffff7040,0xff60f080,0xff6090ff][frame]
            pixels=b''.join(struct.pack('<I',color if (x+y)%3 else 0xffffffff) for y in range(height) for x in range(width))
            chunk=header+pixels;toc.append(struct.pack('<3I',0xfffd0002,24*scale,offset));chunks.append(chunk);offset+=len(chunk)
    path.write_bytes(struct.pack('<4I',0x72756358,16,0x10000,len(toc))+b''.join(toc)+b''.join(chunks))
theme=out/'themes/fs-cursor-test/cursors';theme.mkdir(parents=True,exist_ok=True)
cursor_file(theme/'left_ptr',True);cursor_file(theme/'ew-resize',False)
flags=shlex.split(subprocess.check_output(['pkg-config','--cflags','wayland-server','pixman-1','xkbcommon'],text=True))
module=out/'weston-input.so'
subprocess.run(['cc','-shared','-fPIC','-O2','-Wall','-Wextra','-Werror','-Wno-error=attributes','-I'+str(package/'usr/include/libweston-15'),*flags,'tests/ui/weston-input.c','-o',str(module)],cwd=ROOT,check=True)
display_module=out/'weston-display.so'
if a.regressions:
    protocols=ROOT/'tests/tooling/wayland-protocols'
    for name,xml in [('fractional','staging/fractional-scale/fractional-scale-v1.xml'),('cursor','staging/cursor-shape/cursor-shape-v1.xml'),('tablet','stable/tablet/tablet-v2.xml')]:
        for kind,suffix in [('server-header','-server.h'),('private-code','.c')]:
            subprocess.run(['wayland-scanner',kind,str(protocols/xml),str(out/(name+suffix))],check=True)
    subprocess.run(['cc','-shared','-fPIC','-O2','-Wall','-Wextra','-Werror','-Wno-error=attributes','-I'+str(package/'usr/include/libweston-15'),'-I'+str(out),*flags,'tests/ui/weston-display.c',str(out/'fractional.c'),str(out/'cursor.c'),str(out/'tablet.c'),'-o',str(display_module)],cwd=ROOT,check=True)
reports=[]
for scale,pipeline in [(1,'ir'),(2,'direct')]+([(1,'regression')] if a.regressions else []):
    run=out/f'{scale}x-{pipeline}';run.mkdir(exist_ok=True);binary=run/'cursor-lifecycle'
    if pipeline!='regression':subprocess.run([str(a.compiler.resolve()),'--native-pipeline',pipeline,'tests/ui/wayland-cursor-lifecycle.flex','-o',str(binary)],cwd=ROOT,check=True)
    else:
        for name in ['wayland-cursor','wayland-scaling','wayland-canvas-scale','wayland-input','wayland-clipboard']:
            subprocess.run([str(a.compiler.resolve()),'tests/ui/'+name+'.flex','-o',str(run/name)],cwd=ROOT,check=True)
    env=dict(os.environ)
    for key in ['DISPLAY','WAYLAND_DISPLAY','SWAYSOCK','HYPRLAND_INSTANCE_SIGNATURE','DBUS_SESSION_BUS_ADDRESS']:env.pop(key,None)
    env.update(LD_LIBRARY_PATH=str(package/'usr/lib')+':'+str(package/'usr/lib/weston'),
               WESTON_MODULE_MAP=';'.join(name+'='+str(package/'usr/lib/libweston-15'/name) for name in ['headless-backend.so','gl-renderer.so']),
               XCURSOR_PATH=str(out/'themes'),XCURSOR_THEME='fs-cursor-test',XCURSOR_SIZE='24',FLEX_WESTON_CURSOR_LIFECYCLE='1')
    modules=str(module)
    if pipeline=='regression':
        env.pop('FLEX_WESTON_CURSOR_LIFECYCLE',None);env['FLEX_WESTON_DISPLAY_REPORT']=str(run/'server-report.json');modules+=','+str(display_module)
    with tempfile.TemporaryDirectory(prefix='fs-cursor-') as runtime,(run/'weston.stderr.log').open('wb') as log:
        env.update(XDG_RUNTIME_DIR=runtime,WAYLAND_DISPLAY='fs-cursor-test')
        compositor=subprocess.Popen([str(package/'usr/bin/weston'),'--backend=headless-backend.so','--renderer=gl','--shell='+str(package/'usr/lib/weston/kiosk-shell.so'),'--socket=fs-cursor-test','--width=1600','--height=1000','--scale='+str(scale),'--idle-time=0','--no-config','--fake-seat','--modules='+modules,'--log='+str(run/'weston.log')],env=env,cwd=ROOT,stdout=log,stderr=log,start_new_session=True)
        try:
            until=time.monotonic()+10
            while not (Path(runtime)/env['WAYLAND_DISPLAY']).exists() and compositor.poll() is None and time.monotonic()<until:time.sleep(.02)
            assert compositor.poll() is None and (Path(runtime)/env['WAYLAND_DISPLAY']).exists(),'Private Weston startup failed; inspect logs'
            if pipeline=='regression':
                commands=[['python3','scripts/test-wayland-display.py','--scaling',str(run/'wayland-scaling'),'--cursor',str(run/'wayland-cursor'),'--canvas-scaling',str(run/'wayland-canvas-scale'),'--runtime',runtime,'--display',env['WAYLAND_DISPLAY'],'--server-report',env['FLEX_WESTON_DISPLAY_REPORT'],'--out',str(run/'display')],
                          [str(run/'wayland-cursor'),'animated-close'],[str(run/'wayland-input')],
                          ['python3','scripts/test-wayland-clipboard.py','--binary',str(run/'wayland-clipboard'),'--runtime',runtime,'--display',env['WAYLAND_DISPLAY'],'--out',str(run/'clipboard')]]
                for index,command in enumerate(commands):
                    result=subprocess.run(command,cwd=ROOT,env=env,capture_output=True,timeout=50)
                    (run/f'regression-{index}.stdout.log').write_bytes(result.stdout);(run/f'regression-{index}.stderr.log').write_bytes(result.stderr)
                    assert result.returncode==0,(index,result.returncode,result.stdout,result.stderr)
                reports.append(dict(regressions=True))
            else:
                result=subprocess.run([str(binary)],cwd=ROOT,env=dict(env,WAYLAND_DEBUG='1'),capture_output=True,timeout=15)
                (run/'client.stdout.log').write_bytes(result.stdout);(run/'client.stderr.log').write_bytes(result.stderr)
                assert result.returncode==0,(scale,pipeline,result.returncode,result.stdout,result.stderr[-3000:])
                report=json.loads(result.stdout);assert report['scale']==scale and report['frames']==7 and report['seat_lifecycle'] and report['application_presents']==0,report
                wire=result.stderr.decode();hotspots={(int(x),int(y)) for x,y in re.findall(r'wl_pointer#\d+\.set_cursor\(\d+, wl_surface#\d+, (\d+), (\d+)\)',wire)}
                assert {(2,3),(8,4),(4,10)}<=hotspots,(scale,hotspots)
                assert 'wl_display#1.error(' not in wire,wire[-3000:]
                report.update(pipeline=pipeline,hotspots=sorted(hotspots));reports.append(report)
                (run/'report.json').write_text(json.dumps(report,indent=2)+'\n')
        finally:
            if compositor.poll() is None:
                os.killpg(compositor.pid,signal.SIGTERM)
                try:compositor.wait(timeout=5)
                except subprocess.TimeoutExpired:os.killpg(compositor.pid,signal.SIGKILL);compositor.wait(timeout=5)
        assert compositor.returncode==0,('Private Weston shutdown failed',compositor.returncode)
    (run/'cleanup.json').write_text(json.dumps(dict(compositor_stopped=compositor.poll() is not None,runtime_removed=not Path(runtime).exists()))+'\n')
(out/'report.json').write_text(json.dumps(reports,indent=2)+'\n')
print('PASS private Weston 1x IR / 2x direct: animated cursor frames/hotspots, callbacks, static/leave idle, keyboard/pointer capability recovery, seat removal and zero application repaints')
