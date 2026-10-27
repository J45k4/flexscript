#!/usr/bin/env python3
"""Check shaped caret coordinates against independent HB metrics and GDEF.

The tiny GDEF table added below is a test-only SFNT fixture, not font generation
for the application. It gives a real font uneven ligature carets to ensure the
renderer uses font data rather than always distributing by character count.
"""
import argparse,json,shlex,struct,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--compiler',type=Path,required=True);a=p.parse_args()
out=ROOT/'build/migration/caret-tests';out.mkdir(parents=True,exist_ok=True)
flags=shlex.split(subprocess.check_output(['pkg-config','--cflags','--libs','freetype2','harfbuzz'],text=True))
oracle=out/'oracle';subprocess.run(['cc','-O2',str(ROOT/'tests/tooling/caret-oracle.c'),*flags,'-o',str(oracle)],check=True)
def match(pattern):return Path(subprocess.check_output(['fc-match','-f','%{file}',pattern],text=True))
def measure(font,px,text,direction=0):return json.loads(subprocess.check_output([str(oracle),str(font),str(px),text,*([str(direction)] if direction else [])],text=True))
def checksum(data):
    data+=b'\0'*((-len(data))%4);return sum(struct.unpack('>'+str(len(data)//4)+'I',data))&0xffffffff
def gdef_fixture(source,glyph,parts=3):
    raw=source.read_bytes();tables={}
    for i in range(struct.unpack_from('>H',raw,4)[0]):
        tag,_,offset,size=struct.unpack_from('>4sIII',raw,12+i*16);tables[tag]=raw[offset:offset+size]
    upem=struct.unpack_from('>H',tables[b'head'],18)[0]
    ncarets=parts-1;coords=[upem//5,upem*3//5][:ncarets];lig=struct.pack('>H',ncarets)+b''.join(struct.pack('>H',2+2*ncarets+4*i) for i in range(ncarets))+b''.join(struct.pack('>Hh',1,c) for c in coords)
    tables[b'GDEF']=struct.pack('>IHHHH',0x10000,0,0,12,0)+struct.pack('>HHH',6+len(lig),1,6)+lig+struct.pack('>HHH',1,1,glyph)
    head=bytearray(tables[b'head']);struct.pack_into('>I',head,8,0);tables[b'head']=bytes(head)
    n=len(tables);power=n.bit_length()-1;header=raw[:4]+struct.pack('>HHHH',n,16*(1<<power),power,16*n-16*(1<<power));records=bytearray();body=bytearray();head_offset=0
    for tag,data in sorted(tables.items()):
        offset=12+16*n+len(body);records+=struct.pack('>4sIII',tag,checksum(data),offset,len(data));body+=data+b'\0'*((-len(data))%4)
        if tag==b'head':head_offset=offset
    result=bytearray(header+records+body);struct.pack_into('>I',result,head_offset+8,(0xb1b0afba-checksum(bytes(result)))&0xffffffff)
    assert checksum(bytes(result))==0xb1b0afba
    path=out/f'uneven-ligature-carets-{parts}.ttf';path.write_bytes(result);return path
base=match('Noto Sans');ligature=measure(base,32,'ffi');assert len(ligature['glyphs'])==1,'Conformance needs the Noto Sans ffi ligature (fonts-noto-core)'
special=gdef_fixture(base,ligature['glyphs'][0]['id']);assert len(measure(special,32,'ffi')['glyphs'][0]['carets'])==2
cases=[(match('sans-serif'),16,'AV',[0,1,2]),(base,32,'ffi',[0,1,2,3]),(special,32,'ffi',[0,1,2,3]),
       (base,24,'a\u0301 e\u0308',[0,3,4,7]),(match('sans-serif:charset=5e9'),18,'שלום',[0,2,4,6,8]),
       (match('sans-serif:charset=633'),18,'سلام',[0,2,4,6,8]),(match('sans-serif:charset=4e2d'),16,'中文测试',[0,3,6,9,12]),
       (match('sans-serif:charset=1f44b'),16,'👨‍👩‍👧‍👦',[0,25]),(base,16,'',[0])]
rtl=measure(base,32,'ffi',5);glyph=next(g for g in rtl['glyphs'] if g['cluster']==0);rtlfont=gdef_fixture(base,glyph['id'],2);cases.append((rtlfont,32,'ffi',[0,1,2,3],5))
def expected(run,offsets,n):
    groups={};pen=0
    for glyph in run['glyphs']:
        groups.setdefault(glyph['cluster'],[]).append((pen,glyph));pen+=glyph['advance']
    rtl=run['direction']==5;points={0:pen if rtl else 0,n:0 if rtl else pen};logical=sorted(groups)
    for index,start in enumerate(logical):
        end=logical[index+1] if index+1<len(logical) else n;members=[v for v in offsets if start<=v<=end];items=groups[start];left=min(v[0] for v in items);width=sum(v[1]['advance'] for v in items)
        for k,offset in enumerate(members):
            part=width*k//max(1,len(members)-1)
            glyph=items[0][1]
            if len(items)==1 and len(glyph['carets'])==len(members)-2 and 0<k<len(members)-1 and glyph['unshaped']>0:
                part=glyph['carets'][len(members)-2-k if rtl else k-1]*width//glyph['unshaped'];points[offset]=left+part
            else:points[offset]=left+width-part if rtl else left+part
    return [points[o] for o in offsets],pen
checks=0
for pipeline in ['ir','direct']:
    binary=out/f'carets-{pipeline}';subprocess.run([str(a.compiler.resolve()),'--native-pipeline',pipeline,str(ROOT/'tests/ui/native-carets.flex'),'-o',str(binary)],check=True)
    for case in cases:
        font,px,text,offsets=case[:4];direction=case[4] if len(case)>4 else 0
        run=measure(font,px,text,direction);actual=json.loads(subprocess.check_output([str(binary),str(font),str(px),text,*([str(direction)] if direction else [])],text=True));points,width=expected(run,offsets,len(text.encode()))
        assert actual==dict(offsets=offsets,positions=points,width=(width+63)//64,direction=run['direction']),(pipeline,font,text,run,actual,points)
        checks+=1
print(f'PASS {checks} native caret cases: render-run cache reuse, exact kerning/clusters, uneven font GDEF carets, combining marks, RTL, CJK and color emoji')
