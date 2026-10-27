#!/usr/bin/env python3
"""Native cached GL state against an independent driver oracle, privately."""
import argparse,json,os,stat,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--binary',type=Path,required=True);p.add_argument('--session',type=Path,required=True);p.add_argument('--out',type=Path,required=True);a=p.parse_args()
session=json.loads(a.session.read_text());runtime=Path(session['XDG_RUNTIME_DIR']);assert runtime.name.startswith('fs-ime-') and runtime.stat().st_uid==os.getuid() and stat.S_IMODE(runtime.stat().st_mode)==0o700
assert '/' not in session['WAYLAND_DISPLAY'] and stat.S_ISSOCK((runtime/session['WAYLAND_DISPLAY']).stat().st_mode)
out=a.out.resolve();out.mkdir(parents=True,exist_ok=True);oracle=out/'oracle.so'
subprocess.run(['cc','-shared','-fPIC','-O2','-Wall','-Wextra','-Werror','tests/tooling/renderer-state.c','-lGL','-o',str(oracle)],cwd=ROOT,check=True)
env=dict(os.environ,**session);env.pop('DISPLAY',None);report=out/'report.json';r=subprocess.run([str(a.binary.resolve()),str(oracle),str(report)],cwd=ROOT,env=env,capture_output=True,timeout=20)
(out/'stdout.log').write_bytes(r.stdout);(out/'stderr.log').write_bytes(r.stderr);assert r.returncode==0,(r.returncode,r.stdout,r.stderr[-3000:])
row=json.loads(report.read_text());assert row['byte_identical'] and row['independent_driver_state'] and row['cached_draws']<row['reference_draws'] and row['gl_error']==0,row
print('PASS native renderer state/pixels:',row,flush=True)
