#!/usr/bin/env python3
"""Verify native desktop rendering of the shared UI batches.

First run test-ui.py and test-collie-ui.py to generate actual compiler patches.
Use xvfb-run -a ... --x11 for mapped-window and real X11 input verification.
"""
import argparse,json,os,re,statistics,struct,subprocess,zlib
from pathlib import Path
root=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--compiler',type=Path,required=True)
p.add_argument('--x11',action='store_true',help='Verify native mapped windows and XTest input on the current isolated DISPLAY')
a=p.parse_args();compiler=a.compiler.resolve();build=root/'build';build.mkdir(exist_ok=True)
base_env=dict(os.environ,FLEXSCRIPT_LIB=str(root/'libs'))
for name in ('ui-portable-packets.json','collie-ui-packets.json'):
 assert (build/name).exists(),'Generate '+name+' with scripts/test-ui.py and scripts/test-collie-ui.py first'
def run(cmd,env=None):
 r=subprocess.run(list(map(str,cmd)),cwd=root,env=base_env if env is None else env,capture_output=True,timeout=120)
 assert r.returncode==0,(cmd,r.returncode,r.stdout.decode(errors='replace'),r.stderr.decode(errors='replace'))
 return r.stdout.decode()
run([compiler,'tests/ui/desktop.flex','-o','build/test-ui-desktop'])
run(['cc','-shared','-fPIC','-O2','tests/ui/desktop-events.c','-o','build/ui-desktop-events.so','-ldl'])
env=dict(base_env,SDL_VIDEODRIVER='x11' if a.x11 else 'dummy')
if a.x11:assert env.get('DISPLAY'),'--x11 requires an isolated DISPLAY, e.g. xvfb-run -a'
cmd=['build/test-ui-desktop','build/ui-desktop-events.so']
if a.x11:cmd+=['--x11']
output=run(cmd,env);print(output,end='');count=int(re.search(r'PASS: (\d+)',output)[1]);screens=[]
for name in ('collie','permissions','preview'):
 path=build/('ui-desktop-'+name+'.rgba');raw=path.read_bytes();w,h=430,932
 assert len(raw)==w*h*4,(path,len(raw))
 assert len({raw[i:i+3] for i in range(0,len(raw),4)})>100,'Actual text/image pixels must be rendered'
 def chunk(tag,data):return struct.pack('>I',len(data))+tag+data+struct.pack('>I',zlib.crc32(tag+data)&0xffffffff)
 scan=b''.join(b'\0'+raw[y*w*4:(y+1)*w*4] for y in range(h))
 png=b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',w,h,8,6,0,0,0))+chunk(b'IDAT',zlib.compress(scan))+chunk(b'IEND',b'')
 path.with_suffix('.png').write_bytes(png);screens.append(str(path.with_suffix('.png').relative_to(root)))
run([compiler,'tests/ui/text-rendering.flex','-o','build/test-ui-text'])
text_output=run(['build/test-ui-text'],dict(base_env,SDL_VIDEODRIVER='dummy'))
print(text_output,end='');text_count=int(re.search(r'PASS: (\d+)',text_output)[1])
run([compiler,'tests/ui/tables.flex','-o','build/test-ui-tables'])
table_output=run(['build/test-ui-tables','build/ui-desktop-events.so'],dict(base_env,SDL_VIDEODRIVER='dummy'))
print(table_output,end='')
run([compiler,'tests/ui/markdown-cache.flex','-o','build/test-ui-markdown-cache'])
print(run(['build/test-ui-markdown-cache']),end='')
run([compiler,'tests/ui/scrolling.flex','-o','build/test-ui-scrolling'])
scroll_output=run(['build/test-ui-scrolling','build/ui-desktop-events.so'],dict(base_env,SDL_VIDEODRIVER='dummy'))
print(scroll_output,end='')
run([compiler,'tests/ui/selection-performance.flex','-o','build/test-ui-selection'])
selection_output=run(['build/test-ui-selection','build/ui-selection-performance.json'],dict(base_env,SDL_VIDEODRIVER='dummy'))
print(selection_output,end='');selection=json.loads((build/'ui-selection-performance.json').read_text())
selection_summary={'hit_median_us':statistics.median(selection['hit_us']),'drag_frame_median_us':statistics.median(selection['drag_frame_us']),
                   'warm_drag_layout_builds':selection['warm_drag_layout_builds'],'warm_drag_font_measurements':selection['warm_drag_font_measurements'],
                   'warm_drag_retained_bytes':selection['warm_drag_retained_bytes']}
print('Selection performance:',selection_summary)
for name in ('counter','permissions'):
 run([compiler,'examples/ui/desktop-'+name+'.flex','-o','build/ui-desktop-'+name])
 run(['build/ui-desktop-'+name,'2'],env)
report={'checks':count,'selection_performance':selection_summary,'text_raster_checks':text_count,'text_density_tests':'simulated 1x and 2x framebuffers','backend':'native SDL2 canvas, SDL2_ttf and system image decoder','x11_mapped_windows_and_real_input':a.x11,'same_android_browser_patches':True,'screenshots':screens}
(build/'ui-desktop-report.json').write_text(json.dumps(report,indent=2)+'\n')
print('PASS shared counter and live Collie permissions examples; rendered screenshots verified')
