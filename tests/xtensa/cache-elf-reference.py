#!/usr/bin/env python3
"""Adversarial XIP ELF/NOR-pair validation tests; no firmware execution/device access."""
import argparse,hashlib,json,struct,subprocess
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__)
for name in ('compiler','elf','nor','vendor-elf','vendor-nor','work','report'):p.add_argument('--'+name,type=Path,required=True)
a=p.parse_args();root=Path(__file__).resolve().parents[2];w=a.work.resolve();w.mkdir(exist_ok=True,parents=True);compiler=a.compiler.resolve();binary=w/'check'
q=subprocess.run([str(compiler),str(root/'tests/xtensa/cache-elf.flex'),'-o',str(binary)],cwd=root,capture_output=True,timeout=30);assert q.returncode==0,q.stderr
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def run(elf,nor):return subprocess.run([str(binary),str(elf),str(nor)],cwd=root,capture_output=True,timeout=30)
def parse(b):
 ph=struct.unpack_from('<I',b,28)[0];np=struct.unpack_from('<H',b,44)[0];sh=struct.unpack_from('<I',b,32)[0];ns=struct.unpack_from('<H',b,48)[0];si=struct.unpack_from('<H',b,50)[0];off,size=struct.unpack_from('<II',b,sh+si*40+16);names=b[off:off+size];sections={}
 for i in range(ns):
  at=sh+i*40;no=struct.unpack_from('<I',b,at)[0];name=names[no:].split(b'\0',1)[0].decode();sections[name]=at
 headers=[ph+i*32 for i in range(np)];cached=next(h for h in headers if struct.unpack_from('<I',b,h+8)[0]==0x400d0000);return sections,headers,cached
valid=[]
for name,elf,nor in [('chain',a.elf.resolve(),a.nor.resolve()),('vendor-DROM',a.vendor_elf.resolve(),a.vendor_nor.resolve())]:
 q=run(elf,nor);assert q.returncode==0 and q.stdout==b'PASS: XIP ELF/NOR validated; RAM loaded; cached pages remain gated\n',(name,q.stderr)
 valid.append({'case':name,'ELF_sha256':sha(elf),'NOR_sha256':sha(nor)})
b=a.elf.read_bytes();nor=a.nor.read_bytes();sections,headers,code=parse(b);meta=struct.unpack_from('<I',b,sections['.flex.xip']+16)[0];cf,cn,df,dn=struct.unpack_from('<4I',b,meta);empty=next(h for h in headers if struct.unpack_from('<I',b,h+20)[0]==0)
cases=[]
def patch(name,offset,value,message):
 data=bytearray(b);struct.pack_into('<I',data,offset,value);cases.append((name,data,None,message))
patch('wrong-physical-page-base',meta,cf+65536,'invalid XIP physical page layout')
patch('wrong-IROM-page-count',meta+4,cn+1,'invalid XIP physical page layout')
patch('wrong-DROM-page-base',meta+8,df+65536,'invalid XIP physical page layout')
patch('cached-write-permission',code+24,7,'cached ELF segment and NOR payload differ')
patch('cached-memory-size-mismatch',code+20,struct.unpack_from('<I',b,code+20)[0]+4,'cached ELF segment and NOR payload differ')
patch('cached-physical-address-mismatch',code+12,0x400e0000,'cached ELF segment and NOR payload differ')
patch('cached-bad-alignment',code+28,3,'invalid cached segment alignment')
patch('cached-incongruent-offset',code+4,struct.unpack_from('<I',b,code+4)[0]+1,'invalid cached segment alignment')
patch('cached-NOBITS-section',sections['.irom']+4,8,'cached allocated section is outside emitted payload')
data=bytearray(b);struct.pack_into('<I',data,sections['.data']+12,0x3f400000);struct.pack_into('<I',data,sections['.drom'],0);cases.append(('allocated-DROM-without-region',data,None,'cached allocated section has no emitted region'))
patch('allocated-IROM-outside-payload',sections['.data']+12,0x400d0000+struct.unpack_from('<I',b,sections['.irom']+20)[0]+4,'cached allocated section is outside emitted payload')
patch('unrecognized-cache-program-base',code+8,0x400e0000,'duplicate or missing cached program segments')
patch('empty-segment-has-file-bytes',empty+16,1,'invalid empty load segment')
patch('empty-segment-reserved-flags',empty+24,8,'invalid empty load segment')
patch('normal-RAM-alignment-invalid',headers[0]+28,3,'strict RAM loader rejected derived view')
data=bytearray(b);data[empty:empty+32]=b[code:code+32];cases.append(('duplicate-cached-header',data,None,'duplicate or missing cached program segments'))
f=bytearray(nor);f[cf]^=0xff;cases.append(('wrong-IROM-content',b,f,'cached ELF segment and NOR payload differ'))
f=bytearray(nor);f[4096+32]^=0xff;cases.append(('wrong-SRAM-ROM-content',b,f,'NOR ROM-loadable SRAM image differs from ELF'))
cases.append(('invalid-NOR-geometry',b,nor[:-1],'invalid NOR geometry'))
vendor=a.vendor_elf.read_bytes();vNor=bytearray(a.vendor_nor.read_bytes());vSections,vHeaders,vCode=parse(vendor);vMeta=struct.unpack_from('<I',vendor,vSections['.flex.xip']+16)[0];vDf=struct.unpack_from('<I',vendor,vMeta+8)[0];vNor[vDf]^=0xff;cases.append(('wrong-DROM-content',vendor,vNor,'cached ELF segment and NOR payload differ'))
controls=[]
for name,elf_data,nor_data,message in cases:
 d=w/name;d.mkdir(exist_ok=True);e=d/'input.elf';e.write_bytes(elf_data);f=a.nor.resolve()
 if name=='wrong-DROM-content':f=a.vendor_nor.resolve()
 if nor_data is not None:f=d/'NOR.bin';f.write_bytes(nor_data)
 q=run(e,f);assert q.returncode==1 and message.encode() in q.stderr,(name,q.returncode,q.stdout,q.stderr)
 controls.append({'case':name,'rejected':True,'diagnostic':q.stderr.decode().strip()})
r={'pass':True,'scope_complete':False,'physical_hardware':False,'valid_profiles':valid,'invalid_inputs':controls,'compiler_sha256':sha(compiler),'cached_payloads_executed':False,'scope':'Original linker profile ELF/NOR identity and protected RAM-only load view,including valid empty GNU PHDR and vendor DROM. Guest MMU/cache must still map pages before fetch.'}
a.report.write_text(json.dumps(r,indent=2)+'\n');print('PASS:2 valid cached profiles;',len(controls),'invalid ELF/NOR pairs rejected')
