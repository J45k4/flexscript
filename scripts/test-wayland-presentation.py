#!/usr/bin/env python3
"""Check native presentation records against independent raw Wayland events.

Requires an explicitly private session. Headless compositor feedback is not
physical scanout/input latency or performance acceptance.
"""
import argparse,json,os,re,stat,subprocess
from pathlib import Path
from wayland_commit_check import presentation_commits
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--binary',type=Path,required=True);p.add_argument('--session',type=Path,required=True);p.add_argument('--out',type=Path,required=True);a=p.parse_args()
session=json.loads(a.session.read_text());runtime=Path(session['XDG_RUNTIME_DIR']);assert runtime.name.startswith('fs-ime-') and runtime.stat().st_uid==os.getuid() and stat.S_IMODE(runtime.stat().st_mode)==0o700
assert '/' not in session['WAYLAND_DISPLAY'] and stat.S_ISSOCK((runtime/session['WAYLAND_DISPLAY']).stat().st_mode)
env=dict(os.environ,**session,WAYLAND_DEBUG='1');env.pop('DISPLAY',None);out=a.out.resolve();out.mkdir(parents=True,exist_ok=True)
r=subprocess.run([str(a.binary.resolve()),str(out/'report.json')],env=env,cwd=ROOT,capture_output=True,timeout=15)
(out/'client.stdout.log').write_bytes(r.stdout);(out/'client.stderr.log').write_bytes(r.stderr);assert r.returncode==0,(r.returncode,r.stdout,r.stderr[-3000:])
report=json.loads((out/'report.json').read_text());wire=r.stderr.decode(errors='replace')
manager=int(re.search(r'wl_registry#\d+\.bind\(\d+, "wp_presentation", 1, new id \[unknown\]#(\d+)\)',wire)[1])
assert int(re.search(rf'wp_presentation#{manager}\.clock_id\((\d+)\)',wire)[1])==report['clock_id']
active={};decoded={};outputs={};frame_active=set();frames=0;submitted=0;maximum_frame_active=0
for line in wire.splitlines():
    if m:=re.search(r'wl_registry#\d+\.bind\((\d+), "wl_output", \d+, new id \[unknown\]#(\d+)\)',line):outputs[int(m[2])]=int(m[1])
    if m:=re.search(rf'wp_presentation#{manager}\.feedback\(wl_surface#\d+, new id wp_presentation_feedback#(\d+)\)',line):
        proxy=int(m[1]);assert proxy not in active;submitted+=1;active[proxy]=dict(tag=submitted,status=None,output=0)
    if m:=re.search(r'wp_presentation_feedback#(\d+)\.sync_output\(wl_output#(\d+)\)',line):
        if (proxy:=int(m[1])) in active:active[proxy]['output']=outputs[int(m[2])]
    if m:=re.search(r'wp_presentation_feedback#(\d+)\.presented\(([^)]+)\)',line):
        if (proxy:=int(m[1])) in active:
            hi,lo,ns,refresh,seqhi,seqlo,flags=map(int,m[2].split(','));row=active.pop(proxy);row.update(status=1,presented_ns=((hi<<32)|lo)*1_000_000_000+ns,refresh_ns=refresh,sequence=(seqhi<<32)|seqlo,flags=flags);decoded[row['tag']]=row
    if m:=re.search(r'wp_presentation_feedback#(\d+)\.discarded\(\)',line):
        if (proxy:=int(m[1])) in active:row=active.pop(proxy);row.update(status=2,presented_ns=0,refresh_ns=0,sequence=0,flags=0);decoded[row['tag']]=row
    if '{Default Queue}' in line and (m:=re.search(r'wl_surface#\d+\.frame\(new id wl_callback#(\d+)\)',line)):
        frame_active.add(int(m[1]));maximum_frame_active=max(maximum_frame_active,len(frame_active));frames+=1
    if m:=re.search(r'wl_callback#(\d+)\.done\(',line):frame_active.discard(int(m[1]))
assert submitted==report['submitted']+1==25 and all(row['tag']==25 for row in active.values()) and len(decoded)>=24,(active,decoded,report)
for row in report['rows']:
    expected=decoded[row['tag']]
    assert all(row[key]==value for key,value in expected.items()),(row,expected)
assert frames==25 and report['frame_callbacks']==24 and maximum_frame_active==1 and len(frame_active)<=1,(frames,maximum_frame_active,frame_active)
assert report['cancelled_armed']==report['cancelled_pending']==1
assert report['backend']=='wayland' and not report['sdl_loaded'] and report['gl_error']==0
surface=int(re.search(rf'wp_presentation#{manager}\.feedback\(wl_surface#(\d+),',wire)[1]);commits=presentation_commits(wire,manager,surface);assert commits['presented_buffer_commits']==report['presented'],commits
(out/'commit-check.json').write_text(json.dumps(commits,indent=2)+'\n')
facts=dict(protocol_records=24,frame_requests=frames,frame_callbacks=report['frame_callbacks'],cancelled_pending=1,max_outstanding_frame_callbacks=maximum_frame_active,clock_id=report['clock_id'],flags=sorted({r['flags'] for r in report['rows']}),headless=True,physical_scanout_verified=False)
(out/'wire-check.json').write_text(json.dumps(facts,indent=2)+'\n')
print('PASS native presentation against raw Wayland timestamps, refresh/sequence/flags/output, tag ownership and one outstanding frame callback:',facts,flush=True)

r=subprocess.run([str(a.binary.resolve()),'--swap-failure',str(out/'swap-failure.json')],env=env,cwd=ROOT,capture_output=True,timeout=10)
(out/'swap-failure.stdout.log').write_bytes(r.stdout);(out/'swap-failure.stderr.log').write_bytes(r.stderr);assert r.returncode==0,(r.returncode,r.stdout,r.stderr[-3000:])
row=json.loads((out/'swap-failure.json').read_text());assert row==dict(egl_error=0x3008,frame_ready_after_failure=True,pending=0,cancelled=1,presents=0),row
print('PASS actual EGL bad-display swap: error propagation, no counted presentation, frame unblocked and measurement cancelled',flush=True)
