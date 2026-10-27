#!/usr/bin/env python3
"""Private GPU matrix for direct UI model ownership transfer and compaction."""
import argparse,hashlib,json,os,stat,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--binary',type=Path,action='append',required=True);p.add_argument('--session',type=Path,required=True);p.add_argument('--out',type=Path,required=True);a=p.parse_args()
session=json.loads(a.session.read_text());runtime=Path(session['XDG_RUNTIME_DIR']);assert runtime.name.startswith('fs-ime-') and runtime.stat().st_uid==os.getuid() and stat.S_IMODE(runtime.stat().st_mode)==0o700
assert '/' not in session['WAYLAND_DISPLAY'] and stat.S_ISSOCK((runtime/session['WAYLAND_DISPLAY']).stat().st_mode)
out=a.out.resolve();out.mkdir(parents=True,exist_ok=True);rows=[]
for index,binary in enumerate(a.binary):
    for backend in ['sdl2','wayland']:
        directory=out/f'{index}-{backend}';directory.mkdir(exist_ok=True);report=directory/'report.json'
        env=dict(os.environ,**session,FLEX_GUI_BACKEND=backend,SDL_VIDEODRIVER='wayland',SDL_RENDER_DRIVER='opengl',SDL_VIDEO_WAYLAND_SCALE_TO_DISPLAY='0');env.pop('DISPLAY',None)
        r=subprocess.run([str(binary.resolve()),str(directory/'capture-'),str(report)],cwd=ROOT,env=env,capture_output=True,timeout=45)
        (directory/'stdout.log').write_bytes(r.stdout);(directory/'stderr.log').write_bytes(r.stderr);assert r.returncode==0,(index,backend,r.returncode,r.stdout,r.stderr[-3000:])
        row=json.loads(report.read_text());assert row['backend']==backend and row['checks']==15 and row['byte_identical'] and row['state_identical'] and row['source_arena_released'] and row['compaction_updates']==400 and row['candidate_peak_arena_bytes']<=row['reference_peak_arena_bytes'],row
        rows.append(row);print('PASS model ownership copy:',index,backend,row,flush=True)
sources=['scripts/lib/json.flex','libs/ui/desktop/model.flex','libs/ui/desktop/events.flex','tests/ui/model-copy.flex','scripts/test-model-copy.py']
(out/'report.json').write_text(json.dumps(dict(correctness_only=True,rows=rows,binary_sha256={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in a.binary},source_sha256={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in sources}),indent=2)+'\n')
