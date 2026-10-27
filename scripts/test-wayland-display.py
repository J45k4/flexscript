#!/usr/bin/env python3
"""Check preferred-scale and cursor protocols on an explicitly private server.

Use the test-only weston-display and weston-input modules. Fractional preference
injection is protocol correctness evidence, not a physical mixed-monitor test.
"""
import argparse,json,os,stat,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--scaling',type=Path,required=True);p.add_argument('--cursor',type=Path,required=True)
p.add_argument('--canvas-scaling',type=Path)
p.add_argument('--runtime',type=Path,required=True);p.add_argument('--display',required=True)
p.add_argument('--server-report',type=Path,required=True)
p.add_argument('--out',type=Path,default=ROOT/'build/migration/display-tests')
a=p.parse_args();out=a.out.resolve();out.mkdir(parents=True,exist_ok=True);runtime=a.runtime.resolve()
assert runtime.stat().st_uid==os.getuid() and stat.S_IMODE(runtime.stat().st_mode)==0o700
assert '/' not in a.display and stat.S_ISSOCK((runtime/a.display).stat().st_mode)
env=dict(os.environ,XDG_RUNTIME_DIR=str(runtime),WAYLAND_DISPLAY=a.display);env.pop('DISPLAY',None)
def run(name,args):
    r=subprocess.run([str(x) for x in args],cwd=ROOT,env=env,capture_output=True,timeout=15)
    (out/f'{name}.stderr.log').write_bytes(r.stderr)
    assert r.returncode==0,(name,r.returncode,r.stdout,r.stderr)
    return json.loads(r.stdout)
before=json.loads(a.server_report.read_text())
rows=run('scaling',[a.scaling.resolve(),str(out/'scaling-')])
assert [r['scale'] for r in rows]==[1000,1250,1500,2000,1000],rows
assert all(r['gl_error']==0 for r in rows),rows
assert len({(r['logical_width'],r['logical_height']) for r in rows})==1,rows
for i,r in enumerate(rows):
    assert r['width']==(r['logical_width']*r['scale']+500)//1000
    assert r['height']==(r['logical_height']*r['scale']+500)//1000
    assert (out/f'scaling-{i}.rgba').stat().st_size==r['width']*r['height']*4
cursor=run('cursor',[a.cursor.resolve()]);assert cursor['normal_path']==1 and cursor['fallback_path']==2,cursor
canvas=None
if a.canvas_scaling:
    canvas=run('canvas',[a.canvas_scaling.resolve()]);assert canvas==[1000,1250,1500,2000,1000],canvas
after=json.loads(a.server_report.read_text());assert after['bad_serial']==0 and after['resizes']>before['resizes'] and after['defaults']>before['defaults'],after
(out/'report.json').write_text(json.dumps(dict(scales=rows,cursor=cursor,custom_canvas=canvas,server=after,physical_mixed_output_acceptance=False),indent=2)+'\n')
print('PASS actual scale protocol transitions 1x/1.25x/1.5x/2x/1x, framebuffer/clip pixels, draft/logical bounds, text invalidation, cursor shapes/serials and themed fallback')
