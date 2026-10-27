#!/usr/bin/env python3
"""Independent GL timestamp ABI, pixel and lifetime checks on a private display."""
import argparse,json,os,stat,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--binary',type=Path,required=True);p.add_argument('--session',type=Path,required=True);p.add_argument('--out',type=Path,required=True);a=p.parse_args()
session=json.loads(a.session.read_text());runtime=Path(session['XDG_RUNTIME_DIR']);assert runtime.name.startswith('fs-ime-') and runtime.stat().st_uid==os.getuid() and stat.S_IMODE(runtime.stat().st_mode)==0o700
assert '/' not in session['WAYLAND_DISPLAY'] and stat.S_ISSOCK((runtime/session['WAYLAND_DISPLAY']).stat().st_mode)
out=a.out.resolve();out.mkdir(parents=True,exist_ok=True);oracle=out/'oracle.so'
subprocess.run(['cc','-shared','-fPIC','-O2','-Wall','-Wextra','-Werror','tests/tooling/gpu-timing.c','-lGL','-o',str(oracle)],cwd=ROOT,check=True)
rows=[]
for backend in ['sdl2','wayland']:
    env=dict(os.environ,**session,FLEX_GUI_BACKEND=backend,SDL_VIDEODRIVER='wayland');env.pop('DISPLAY',None)
    report=out/(backend+'.json');r=subprocess.run([str(a.binary.resolve()),str(oracle),str(report)],cwd=ROOT,env=env,capture_output=True,timeout=20)
    (out/(backend+'.stdout.log')).write_bytes(r.stdout);(out/(backend+'.stderr.log')).write_bytes(r.stderr)
    assert r.returncode==0,(backend,r.returncode,r.stdout,r.stderr[-3000:])
    row=json.loads(report.read_text());assert row['backend']==backend and row['timer_bits']==64 and row['independent_oracle'] and row['identical_pixels'] and row['owned_cleanup'],row
    assert len(row['rows'])==3 and all(q['start_ns']>2**32 and q['end_ns']>=q['start_ns'] and q['elapsed_ns']==q['end_ns']-q['start_ns'] for q in row['rows']),row
    if row.get('includes_present_call'):
        assert row.get('explicit_final_flush') and all(q['start_ns']<=q['draw_end_ns']<=q['present_start_ns']<=q['end_ns'] and q['draw_elapsed_ns']==q['draw_end_ns']-q['start_ns'] and q['present_elapsed_ns']==q['end_ns']-q['present_start_ns'] and q['elapsed_ns']==q['draw_elapsed_ns']+(q['present_start_ns']-q['draw_end_ns'])+q['present_elapsed_ns'] for q in row['rows']),row
    rows.append(row)
    print('PASS',backend,'GPU timestamp query: 64-bit ABI, deferred availability, unchanged pixels and query/context cleanup',flush=True)
(out/'report.json').write_text(json.dumps(dict(correctness_only=True,physical_scanout_verified=False,rows=rows),indent=2)+'\n')
