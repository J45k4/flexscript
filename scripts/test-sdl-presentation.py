#!/usr/bin/env python3
"""Validate an optional SDL Wayland timing observer on a private compositor.

Public C headers/functions are independent test oracles, never shipped helpers.
Compositor feedback with zero hardware flags is not physical scanout proof.
"""
import argparse,json,os,re,shlex,signal,stat,subprocess,time
from pathlib import Path
from wayland_commit_check import presentation_commits
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--binary',type=Path,required=True);p.add_argument('--session',type=Path,required=True);p.add_argument('--out',type=Path,required=True);a=p.parse_args()
session=json.loads(a.session.read_text());runtime=Path(session['XDG_RUNTIME_DIR']);assert runtime.name.startswith('fs-ime-') and runtime.stat().st_uid==os.getuid() and stat.S_IMODE(runtime.stat().st_mode)==0o700
assert '/' not in session['WAYLAND_DISPLAY'] and stat.S_ISSOCK((runtime/session['WAYLAND_DISPLAY']).stat().st_mode)
out=a.out.resolve();out.mkdir(parents=True,exist_ok=True);env=dict(os.environ,**session,WAYLAND_DEBUG='1',SDL_VIDEODRIVER='wayland',FLEX_GUI_BACKEND='sdl2');env.pop('DISPLAY',None);env.pop('SDL_VIDEO_DRIVER',None)
flags=shlex.split(subprocess.check_output(['pkg-config','--cflags','--libs','sdl2','wayland-client'],text=True));source=ROOT/'tests/tooling/sdl-wayland.c';oracle=out/'oracle.so';abi=out/'abi'
subprocess.run(['cc','-DSDL_OBSERVER_MAIN','-O2','-Wall','-Wextra','-Werror',str(source),'-o',str(abi),*flags],check=True)
assert subprocess.check_output([str(abi)],text=True).strip()=='72 4 8 16 6','Public SDL SysWMinfo ABI differs'
subprocess.run(['cc','-shared','-fPIC','-O2','-Wall','-Wextra','-Werror',str(source),'-o',str(oracle),*flags],check=True)
stage=out/'stage';stage.unlink(missing_ok=True)
with (out/'client.stdout.log').open('wb') as stdout,(out/'client.stderr.log').open('wb') as stderr:
    app=subprocess.Popen([str(a.binary.resolve()),str(oracle),str(stage),str(out/'report.json')],env=env,cwd=ROOT,stdout=stdout,stderr=stderr,start_new_session=True)
    try:
        for name in ['input-before','input-after']:
            until=time.monotonic()+10
            while time.monotonic()<until and app.poll() is None:
                if stage.exists() and stage.read_text()==name:break
                time.sleep(.01)
            assert app.poll() is None and stage.exists() and stage.read_text()==name,('SDL fixture failed',name,app.poll(),(out/'client.stderr.log').read_bytes()[-2000:])
            subprocess.run(['wtype','-s','200','-k','Escape','-s','50'],env=env,check=True,capture_output=True,timeout=3)
        assert app.wait(timeout=10)==0,(out/'client.stderr.log').read_bytes()[-3000:]
    finally:
        if app.poll() is None:os.killpg(app.pid,signal.SIGTERM);app.wait(timeout=5)
report=json.loads((out/'report.json').read_text());wire=(out/'client.stderr.log').read_text(errors='replace');manager=report['manager_proxy_id'];surface=report['surface_proxy_id'];active={};decoded={};outputs={};submitted=0
assert re.search(rf'wl_registry#{report["registry_proxy_id"]}\.bind\(\d+, "wp_presentation", 1, new id \[unknown\]#{manager}\)',wire)
assert int(re.search(rf'wp_presentation#{manager}\.clock_id\((\d+)\)',wire)[1])==report['clock_id']
for line in wire.splitlines():
    if m:=re.search(r'wl_registry#\d+\.bind\((\d+), "wl_output", \d+, new id \[unknown\]#(\d+)\)',line):outputs[int(m[2])]=int(m[1])
    if m:=re.search(rf'wp_presentation#{manager}\.feedback\(wl_surface#{surface}, new id wp_presentation_feedback#(\d+)\)',line):
        proxy=int(m[1]);assert proxy not in active;submitted+=1;active[proxy]=dict(tag=submitted,status=None,output=0)
    if m:=re.search(r'wp_presentation_feedback#(\d+)\.sync_output\(wl_output#(\d+)\)',line):
        if (proxy:=int(m[1])) in active:active[proxy]['output']=outputs[int(m[2])]
    if m:=re.search(r'wp_presentation_feedback#(\d+)\.presented\(([^)]+)\)',line):
        if (proxy:=int(m[1])) in active:
            hi,lo,ns,refresh,seqhi,seqlo,flags=map(int,m[2].split(','));row=active.pop(proxy);row.update(status=1,presented_ns=((hi<<32)|lo)*1_000_000_000+ns,refresh_ns=refresh,sequence=(seqhi<<32)|seqlo,flags=flags);decoded[row['tag']]=row
    if m:=re.search(r'wp_presentation_feedback#(\d+)\.discarded\(\)',line):
        if (proxy:=int(m[1])) in active:row=active.pop(proxy);row.update(status=2,presented_ns=0,refresh_ns=0,sequence=0,flags=0);decoded[row['tag']]=row
assert not active and submitted==len(decoded)==report['submitted']==24,(active,decoded,report)
for row in report['rows']:
    expected=decoded[row['tag']];assert all(row[k]==v for k,v in expected.items()),(row,expected)
assert report['backend']=='sdl2' and report['frame_callbacks']==24 and report['reopens']==6 and report['borrowed_connection_survived'] and report['real_keyboard_before_after'] and report['sdl_queue_survived'],report
commits=presentation_commits(wire,manager,surface);assert commits['presented_buffer_commits']==sum(row['status']==1 for row in report['rows']),commits
(out/'commit-check.json').write_text(json.dumps(commits,indent=2)+'\n')
facts=dict(public_abi='72 4 8 16 6',protocol_records=24,clock_id=report['clock_id'],flags=sorted({r['flags'] for r in report['rows']}),real_input_before_after=True,borrowed_connection_survived=True,registry_reused_for_six_reopens=True,headless=True,physical_scanout_verified=False)
(out/'wire-check.json').write_text(json.dumps(facts,indent=2)+'\n')
print('PASS SDL observer: public ABI/pointers, raw presentation timestamps, real keyboard input before/after teardown, SDL event queue and registry/connection ownership:',facts,flush=True)
