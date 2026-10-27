#!/usr/bin/env python3
"""Paired same-process image benchmarks against the installed GDK Pixbuf.

Both paths decode the same bytes, use area/linear filtering and the same
1536-pixel/512-KiB JPEG-85/70/50 preview policy. The C oracle encodes in memory,
avoiding the old application's temporary file. No codec library is hidden.
"""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import random
import statistics
import subprocess
import time
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageStat

ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--compiler',type=Path,default=ROOT/'build/collie-desktop/compiler')
p.add_argument('--out',type=Path,default=ROOT/'build/image/benchmark')
p.add_argument('--report',type=Path,default=ROOT/'libs/image/benchmark-results.json')
p.add_argument('--samples',type=int,default=5);p.add_argument('--rounds',type=int,default=5)
p.add_argument('--cpu',type=int,default=3);a=p.parse_args();out=a.out.resolve();out.mkdir(parents=True,exist_ok=True)
assert a.samples>=3 and a.rounds>=1
compiler=a.compiler.resolve();driver=out/'driver';reference=out/'reference.so'
subprocess.run([str(compiler),str(ROOT/'tests/image/driver.flex'),'-o',str(driver)],check=True)
flags=subprocess.check_output(['pkg-config','--cflags','--libs','gdk-pixbuf-2.0'],text=True).split()
subprocess.run(['cc','-O3','-shared','-fPIC',str(ROOT/'tests/image/reference.c'),'-o',str(reference),*flags],check=True)

def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def texture(w,h,seed):
    noise=Image.frombytes('L',(w,h),random.Random(seed).randbytes(w*h)).filter(ImageFilter.GaussianBlur(1.2))
    vertical=Image.linear_gradient('L').resize((w,h));horizontal=Image.linear_gradient('L').rotate(90).resize((w,h))
    return Image.merge('RGB',(Image.blend(vertical,noise,.45),Image.blend(horizontal,noise,.55),Image.blend(ImageChops.invert(vertical),noise,.65)))

# All generated cases are deterministic and distinct from tuning/unit fixtures.
photo=texture(3072,2048,8675309);cases=[]
for suffix,options in [('png',{}),('jpg',dict(quality=90)),('webp',dict(quality=90))]:
    path=out/('texture.'+suffix);photo.save(path,**options);cases.append(('procedural texture '+suffix.upper(),path))
screen=Image.new('RGBA',(2048,1280),'#13181e');draw=ImageDraw.Draw(screen)
for y in range(20,1220,60):
    draw.rounded_rectangle((30,y,580,y+45),radius=10,fill=('#324a39' if y%120==20 else '#242e35'))
    draw.text((50,y+14),'Collie projects, conversations and native image previews',fill='#deeadb')
    draw.rectangle((650,y+4,1980,y+40),fill=('#2e5149' if y%120==20 else '#303b4d'))
screen.save(out/'screen.png');cases.append(('procedural desktop RGBA PNG',out/'screen.png'))
portrait=texture(2048,3072,20817);exif=Image.Exif();exif[274]=6;portrait.save(out/'portrait.jpg',quality=90,exif=exif)
cases.append(('portrait JPEG / EXIF 6',out/'portrait.jpg'))
alpha=Image.new('RGBA',(1024,768));draw=ImageDraw.Draw(alpha)
for y in range(20,700,70):draw.rounded_rectangle((20,y,1000,y+55),radius=25,fill=(80+y//4,170,110,32+y//4))
alpha.save(out/'alpha.png');cases.append(('small transparent PNG',out/'alpha.png'))
texture(640,480,314159).save(out/'small.jpg',quality=90);cases.append(('small JPEG',out/'small.jpg'))
logo=ROOT/'apps/collie/android/res/drawable-nodpi/collie_border_collie.png';cases.append(('Collie logo PNG',logo))
noise=Image.frombytes('RGB',(2048,1536),random.Random(70001).randbytes(2048*1536*3));noise.save(out/'noise.png')
cases.append(('incompressible PNG / budget boundary',out/'noise.png'))
noise.crop((0,0,1536,1536)).save(out/'noise-no-resize.png')
cases.append(('incompressible PNG / budget rejection',out/'noise-no-resize.png'))

def metrics(a,b):
    assert a.size==b.size,(a.size,b.size)
    d=ImageChops.difference(a.convert('RGB'),b.convert('RGB'));rms=ImageStat.Stat(d).rms
    rmse=math.sqrt(sum(x*x for x in rms)/3)
    return dict(rmse=rmse,psnr_db=20*math.log10(255/rmse) if rmse else None,max_error=max(x[1] for x in d.getextrema()))

def resize_metrics(native,reference,size):
    left=Image.frombytes('RGBA',size,native.read_bytes());right=Image.frombytes('RGBA',size,reference.read_bytes())
    comparisons=[]
    for color in ['black','white']:
        comparisons.append(metrics(Image.alpha_composite(Image.new('RGBA',size,color),left),Image.alpha_composite(Image.new('RGBA',size,color),right)))
    return dict(composite_rmse=max(x['rmse'] for x in comparisons),max_error=max(x['max_error'] for x in comparisons))

available=os.sched_getaffinity(0);cpu=a.cpu if a.cpu in available else min(available);os.sched_setaffinity(0,{cpu})
rows=[]
for index,(name,path) in enumerate(cases):
    w,h=Image.open(path).size;scale=min(1,1536/max(w,h));dw=max(1,int(w*scale));dh=max(1,int(h*scale))
    prefix=out/f'case-{index}';config=prefix.with_suffix('.json')
    files={key:Path(str(prefix)+'-'+key+suffix) for key,suffix in [('native_resize_output','.rgba'),('reference_resize_output','.rgba'),('native_preview_output','.jpg'),('reference_preview_output','.jpg')]}
    request=dict(input=str(path.resolve()),operation='benchmark',oracle=str(reference),width=dw,height=dh,side=1536,limit=524288,samples=a.samples,rounds=a.rounds,**{k:str(v) for k,v in files.items()})
    config.write_text(json.dumps(request));result=subprocess.run([str(driver),str(config)],capture_output=True,timeout=300)
    assert result.returncode==0,(name,result.returncode,result.stderr.decode(errors='replace'))
    measured=json.loads(result.stdout);row=dict(name=name,width=w,height=h,output_width=dw,output_height=dh,input_bytes=path.stat().st_size,input_sha256=digest(path),**measured)
    row['medians_ms']={};row['speedup']={}
    for stage in ['decode','resize','preview']:
        native=statistics.median(x[stage+'_ns'] for x in measured['measurements'] if x['native'])/1e6
        baseline=statistics.median(x[stage+'_ns'] for x in measured['measurements'] if not x['native'])/1e6
        row['medians_ms'][stage]=dict(flexscript=native,gdk_pixbuf=baseline);row['speedup'][stage]=baseline/native
    row['resize_quality']=resize_metrics(files['native_resize_output'],files['reference_resize_output'],(dw,dh))
    row['comparable_preview']=bool(measured['native_preview_ok'] and measured['reference_preview_ok'] and measured['native_quality']==measured['reference_quality'])
    if measured['native_preview_ok'] and measured['reference_preview_ok']:
        row['preview_quality']=metrics(Image.open(files['native_preview_output']),Image.open(files['reference_preview_output']))
        assert row['preview_quality']['rmse']<8,(name,row['preview_quality'])
    rows.append(row)
    print(f"{name}: preview {row['speedup']['preview']:.2f}x, resize {row['speedup']['resize']:.2f}x, decode {row['speedup']['decode']:.2f}x; preview_ok={measured['native_preview_ok']}",flush=True)

successful=[r for r in rows if r['comparable_preview']]
report=dict(platform=platform.platform(),cpu=cpu,cpu_model=next((x.split(':',1)[1].strip() for x in Path('/proc/cpuinfo').read_text().splitlines() if x.startswith('model name')),''),
            compiler_sha256=digest(compiler),driver_sha256=digest(driver),gdk_pixbuf_version=subprocess.check_output(['pkg-config','--modversion','gdk-pixbuf-2.0'],text=True).strip(),
            samples=a.samples,rounds=a.rounds,order='alternating backend order each paired sample; equal warmups; one pinned CPU; same process',
            fixture_scope='one repository image plus deterministic procedural fixtures; no claim about all photographs or codec implementations',
            codec_backends=dict(png='libpng16',jpeg='libturbojpeg',webp='libwebp / libwebpdemux for first animated frame'),
            aggregate_scope='only successful previews with matched JPEG quality; differing success/quality and rejected cases remain in rows but are excluded',
            preview_geomean_speedup=math.exp(sum(math.log(r['speedup']['preview']) for r in successful)/len(successful)),
            preview_wins=sum(r['speedup']['preview']>1 for r in successful),preview_cases=len(successful),rows=rows)
a.report.resolve().parent.mkdir(parents=True,exist_ok=True);a.report.resolve().write_text(json.dumps(report,indent=2)+'\n')
print(f"Complete successful previews: {report['preview_geomean_speedup']:.2f}x geometric mean, {report['preview_wins']}/{report['preview_cases']} wins")
