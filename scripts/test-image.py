#!/usr/bin/env python3
"""Native image ownership, codecs, orientation, filter quality and SIMD parity.

Pillow and GDK Pixbuf are independent test oracles, never application backends.
"""
import argparse
import io
import json
import math
import os
from pathlib import Path
import random
import struct
import subprocess
import tempfile
import zlib
from PIL import Image

ROOT=Path(__file__).resolve().parents[1]
COMPILER=Path(os.environ.get('FLEX_COMPILER',ROOT/'build/collie-desktop/compiler')).resolve()
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--pipeline',choices=['ir','direct'],default='ir')
args=parser.parse_args()
checks=0

def chunk(tag,data):
    return struct.pack('>I',len(data))+tag+data+struct.pack('>I',zlib.crc32(tag+data))

def png_rgba(image,interlace=False):
    w,h=image.size;raw=image.tobytes();body=b''
    passes=[(0,0,1,1)] if not interlace else [(0,0,8,8),(4,0,8,8),(0,4,4,8),(2,0,4,4),(0,2,2,4),(1,0,2,2),(0,1,1,2)]
    for x0,y0,dx,dy in passes:
        if x0>=w or y0>=h:continue
        for y in range(y0,h,dy):body+=b'\0'+b''.join(raw[(y*w+x)*4:(y*w+x+1)*4] for x in range(x0,w,dx))
    return b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',w,h,8,6,0,0,int(interlace)))+chunk(b'IDAT',zlib.compress(body))+chunk(b'IEND',b'')

def axis(src,dst,x):
    if dst>=src:
        pos=max(0.,min(src-1.,(x+.5)*src/dst-.5));start=int(pos);fraction=pos-start
        return [(start,1-fraction)]+([(start+1,fraction)] if fraction else [])
    left=x*src/dst;right=(x+1)*src/dst
    return [(s,(min(s+1,right)-max(s,left))/(right-left)) for s in range(int(left),math.ceil(right))]

def ideal_resize(image,size):
    sw,sh=image.size;w,h=size;data=list(pixels(image));horizontal=[]
    for y in range(sh):
        row=[]
        for x in range(w):
            sums=[0.,0.,0.,0.]
            for sx,weight in axis(sw,w,x):
                p=data[y*sw+sx];a=p[3]/255
                for k in range(3):sums[k]+=p[k]*a*weight
                sums[3]+=p[3]*weight
            row.append(sums)
        horizontal.append(row)
    result=[]
    for y in range(h):
        for x in range(w):
            sums=[0.,0.,0.,0.]
            for sy,weight in axis(sh,h,y):
                for k in range(4):sums[k]+=horizontal[sy][x][k]*weight
            result.append(sums)
    return result

def premul(data):
    return [(p[0]*p[3]/255,p[1]*p[3]/255,p[2]*p[3]/255,p[3]) for p in data]

def pixels(image):
    return image.get_flattened_data() if hasattr(image,'get_flattened_data') else image.getdata()

with tempfile.TemporaryDirectory(prefix='image-',dir=ROOT/'build') as directory:
    work=Path(directory);driver=work/'driver'
    subprocess.run([str(COMPILER),'--native-pipeline',args.pipeline,str(ROOT/'tests/image/driver.flex'),'-o',str(driver)],check=True)
    def run(path,operation='decode',**options):
        global checks
        out=work/'out';config=work/'request.json';config.write_text(json.dumps(dict(input=str(path),output=str(out),operation=operation,**options)))
        result=subprocess.run([str(driver),str(config)],capture_output=True,timeout=20)
        assert result.returncode==0,(result.returncode,result.stderr.decode(errors='replace'))
        view=json.loads(result.stdout);checks+=1
        return view,out.read_bytes() if 'error' not in view else b''
    rng=random.Random(1729);rgba=Image.frombytes('RGBA',(73,57),rng.randbytes(73*57*4))
    rgb=rgba.convert('RGB');fixtures=[]
    for mode in ['RGB','RGBA','L','LA','1','P']:
        image=rgba.convert(mode);p=work/(mode+'.png')
        if mode=='P':image.info['transparency']=bytes(range(256))
        image.save(p);fixtures.append(p)
    p=work/'adam7.png';p.write_bytes(png_rgba(rgba,True));fixtures.append(p)
    for progressive in [False,True]:
        p=work/f'jpeg-{progressive}.jpg';rgb.save(p,quality=90,progressive=progressive);fixtures.append(p)
    p=work/'gray.jpg';rgb.convert('L').save(p);fixtures.append(p)
    p=work/'cmyk.jpg';rgb.convert('CMYK').save(p);fixtures.append(p)
    for lossless in [False,True]:
        p=work/f'webp-{lossless}.webp';rgba.save(p,lossless=lossless,quality=90);fixtures.append(p)
    p=work/'animated.webp';rgba.save(p,save_all=True,append_images=[rgba.transpose(Image.Transpose.FLIP_LEFT_RIGHT)],duration=100,loop=0,lossless=True);fixtures.append(p)
    for p in fixtures:
        view,data=run(p);assert 'error' not in view,(p.name,view)
        expected=Image.open(p).convert('RGBA');assert (view['width'],view['height'])==expected.size
        delta=max(abs(a-b) for a,b in zip(data,expected.tobytes()))
        assert delta<=2,(p.name,delta)
    print('PASS PNG modes/Adam7, baseline/progressive/grayscale/CMYK JPEG, lossy/lossless/animated WebP decode',flush=True)

    for width in range(1,10):
        tiny=work/'tiny-rgb.png';Image.frombytes('RGB',(width,1),rng.randbytes(width*3)).save(tiny)
        _,scalar=run(tiny,acceleration=0);_,fast=run(tiny,acceleration=1)
        assert scalar==fast==Image.open(tiny).convert('RGBA').tobytes(),width
    # Unmarked 16-bit samples are interpreted as sRGB, including alpha.
    for channels,color in [(1,0),(4,6)]:
        values=[0,257,32896,65535]*channels
        raw=struct.pack('>'+str(len(values))+'H',*values)
        sixteen=work/'sixteen.png';sixteen.write_bytes(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',4,1,16,color,0,0,0))+chunk(b'IDAT',zlib.compress(b'\0'+raw))+chunk(b'IEND',b''))
        view,data=run(sixteen);assert 'error' not in view,view
        if channels==1:expected=b''.join(bytes([v//257]*3+[255]) for v in values)
        else:expected=bytes(v//257 for v in values)
        assert max(abs(a-b) for a,b in zip(data,expected))<=1,(channels,data,expected)
    print('PASS scalar/native RGB expansion tails and 16-bit grayscale/RGBA PNG samples',flush=True)

    p=work/'RGBA.png'
    for orientation in range(1,9):
        transpose={1:None,2:Image.Transpose.FLIP_LEFT_RIGHT,3:Image.Transpose.ROTATE_180,4:Image.Transpose.FLIP_TOP_BOTTOM,
                   5:Image.Transpose.TRANSPOSE,6:Image.Transpose.ROTATE_270,7:Image.Transpose.TRANSVERSE,8:Image.Transpose.ROTATE_90}[orientation]
        view,data=run(p,'orient',orientation=orientation);expected=rgba if transpose is None else rgba.transpose(transpose)
        assert data==expected.tobytes(),orientation
        scalar,plain=run(p,'orient',orientation=orientation,acceleration=0);assert plain==data,(orientation,scalar)
        exif=Image.Exif();exif[274]=orientation
        for fmt in ['PNG','JPEG','WEBP']:
            tagged=work/('tagged.'+fmt.lower());rgba.convert('RGB').save(tagged,format=fmt,exif=exif)
            view,_=run(tagged);assert view['orientation']==orientation,(fmt,orientation,view)
    print('PASS all eight exact pixel orientations and bounded PNG/JPEG/WebP EXIF metadata',flush=True)

    for alpha in [False,True]:
        image=rgba.copy()
        if not alpha:image.putalpha(255)
        path=work/'resize.png';image.save(path)
        for w,h in [(1,1),(2,7),(73,57),(111,97),(13,11),(73,8),(15,57),(1,57),(73,1),(72,56),(7,101)]:
            scalar,first=run(path,'resize',width=w,height=h,acceleration=0)
            native,second=run(path,'resize',width=w,height=h,acceleration=1)
            assert 'error' not in native and first==second,(alpha,w,h,native)
            actual=premul(pixels(Image.frombytes('RGBA',(w,h),second)));ideal=ideal_resize(image,(w,h))
            worst=max(abs(a-b) for x,y in zip(actual,ideal) for a,b in zip(x,y))
            assert worst<=2.1,(alpha,w,h,worst)
    print('PASS scalar/SSE4.1 byte identity, degenerate axes, enlargement and antialiased reductions against independent area/linear arithmetic',flush=True)

    for path in fixtures:
        view,data=run(path,'png');assert 'error' not in view,(path.name,view)
        original=Image.open(path).convert('RGBA');roundtrip=Image.open(io.BytesIO(data)).convert('RGBA')
        assert roundtrip.size==original.size and max(abs(a-b) for a,b in zip(roundtrip.tobytes(),original.tobytes()))<=2
        view,data=run(path,'jpeg',quality=85);assert 'error' not in view,(path.name,view)
        saved=Image.open(io.BytesIO(data));assert saved.size==original.size and saved.format=='JPEG'
        view,data=run(path,'preview',side=32,limit=524288);assert 'error' not in view,(path.name,view)
        saved=Image.open(io.BytesIO(data));assert max(saved.size)<=32 and len(data)<=524288
    print('PASS native owned PNG/JPEG output and bounded complete orientation/resize/preview pipelines',flush=True)

    # Reject oversized headers before full pixel allocation, and malformed input.
    huge=b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',100000,100000,8,6,0,0,0))+chunk(b'IDAT',zlib.compress(b''))+chunk(b'IEND',b'')
    invalid=[b'',b'not an image',huge,png_rgba(rgba)[:33]]
    for source in [work/'RGBA.png',work/'jpeg-False.jpg',work/'webp-True.webp']:
        raw=source.read_bytes();invalid.extend(raw[:n] for n in [1,8,17,len(raw)//2])
    for index,data in enumerate(invalid):
        bad=work/f'bad-{index}';bad.write_bytes(data);view,_=run(bad);assert view.get('error'),(index,view)
    for options in [dict(width=0,height=1),dict(width=100000,height=100000)]:
        view,_=run(p,'resize',**options);assert view.get('error'),view
    view,_=run(p,'preview',side=0);assert view.get('error'),view
    print(f'PASS {checks} image checks, malformed/truncated streams, dimension limits and ownership paths',flush=True)
