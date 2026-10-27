#!/usr/bin/env python3
"""Private GPU matrix for bounded same-pass measurement reuse."""
import argparse, hashlib, json, os, stat, subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--binary',type=Path,action='append',required=True)
p.add_argument('--session',type=Path,required=True)
p.add_argument('--out',type=Path,required=True)
a=p.parse_args();session=json.loads(a.session.read_text());runtime=Path(session['XDG_RUNTIME_DIR'])
assert runtime.name.startswith('fs-ime-') and runtime.stat().st_uid==os.getuid() and stat.S_IMODE(runtime.stat().st_mode)==0o700
assert '/' not in session['WAYLAND_DISPLAY'] and stat.S_ISSOCK((runtime/session['WAYLAND_DISPLAY']).stat().st_mode)
out=a.out.resolve();out.mkdir(parents=True,exist_ok=True);rows=[]
for index,binary in enumerate(a.binary):
    for backend in ['sdl2','wayland']:
        prefix=out/f'{index}-{backend}';report=prefix.with_suffix('.json')
        env=dict(os.environ,**session,FLEX_GUI_BACKEND=backend,SDL_VIDEODRIVER='wayland',SDL_RENDER_DRIVER='opengl',SDL_VIDEO_WAYLAND_SCALE_TO_DISPLAY='0');env.pop('DISPLAY',None)
        r=subprocess.run([str(binary.resolve()),str(report)],cwd=ROOT,env=env,capture_output=True,timeout=40)
        prefix.with_suffix('.stdout.log').write_bytes(r.stdout);prefix.with_suffix('.stderr.log').write_bytes(r.stderr)
        assert r.returncode==0,(index,backend,r.returncode,r.stdout,r.stderr[-3000:])
        row=json.loads(report.read_text());assert row['backend']==backend and row['checks']==row['reused_draws']==20 and row['ancestor_reflow'] and row['byte_identical'] and row['geometry_identical'] and row['gl_error']==0 and row['cache_bytes']==32768,row
        rows.append(row);print('PASS same-pass measurement reuse:',index,backend,row,flush=True)
sources=['libs/ui/desktop.flex','libs/ui/desktop/model.flex','libs/ui/desktop/layout.flex','libs/gui/metrics.flex','tests/ui/measure-reuse.flex','scripts/test-measure-reuse.py']
(out/'report.json').write_text(json.dumps(dict(correctness_only=True,rows=rows,binary_sha256={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in a.binary},source_sha256={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in sources}),indent=2)+'\n')
