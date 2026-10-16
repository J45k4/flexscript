#!/usr/bin/env python3
"""SDK-addressed functional64KiB flash/cache tests; no hardware or ROM stubs.

The current model intentionally does not claim illegal-access trap parity,
other page modes,buses or full SPI/NOR command support.
"""
from emulator_sources import source_path, clone_source
import argparse,hashlib,json,re,shutil,subprocess
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__)
for n in ('compiler','reference','work','report'):p.add_argument('--'+n,type=Path,required=True)
p.add_argument('--cc',default='cc');a=p.parse_args();root=Path(__file__).resolve().parents[2];w=a.work.resolve();w.mkdir(exist_ok=True,parents=True);compiler=a.compiler.resolve();refs=a.reference.resolve()
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
headers={}
for v in json.loads((root/'tests/xtensa/clock-oracle/sources.json').read_text()):
 if v['name'] in ('sdk-dport-reg.h','soc-reg-base.h'):
  assert sha(refs/v['name'])==v['sha256'];headers[v['name']]=v['sha256']
assert len(headers)==2
inc=w/'include';inc.mkdir(exist_ok=True);shutil.copyfile(refs/'sdk-dport-reg.h',inc/'dport_reg.h');shutil.copyfile(refs/'soc-reg-base.h',inc/'reg_base.h')
def run(args):return subprocess.run([str(x) for x in args],cwd=root,capture_output=True,timeout=45)
def checked(args):
 q=run(args);assert q.returncode==0,(args,q.stdout,q.stderr);return q
c=w/'C-reference';raw=w/'reference.bin';checked([a.cc,'-std=gnu11','-O2','-Wall','-Wextra','-Werror','-I'+str(root/'tests/esp32/i2s-oracle'),'-I'+str(inc),root/'tests/xtensa/cache-oracle/reference.c','-o',c]);raw.write_bytes(checked([c]).stdout);assert raw.stat().st_size==136
source=root/'tests/xtensa/cache-model.flex';binary=w/'model';checked([compiler,source,'-o',binary]);q=checked([binary,raw]);m=re.fullmatch(rb'Cache model: (\d+) checks passed\n',q.stdout);assert m;checks=int(m[1])
modules=('esp32-emulator.flex','esp32-cache-emulator.flex','esp32-clock-emulator.flex','esp32-gpio-emulator.flex','esp32-gpio-pads.flex','esp32-spi-emulator.flex','esp32-rmt-emulator.flex','esp32-i2c-emulator.flex','esp32-i2s-emulator.flex')
mutations=[
('cache-global-enable-ignored','let enabled=(ctrl&8)!=0;','let enabled=1;'),
('DROM-mask-ignored','enabled && !(cfg&16)','enabled'),
('IROM-mask-ignored','enabled && !(cfg&1)','enabled'),
('flush-does-not-refresh','if flush{refresh=3;}',''),
('last-physical-page-rejected','at+65536<=load64(p+8)','at+65536<load64(p+8)'),
('invalid-MMU-bit-discarded','store64(at,value&511)','store64(at,value&255)'),
('APP-MMU-overwrites-PRO','((address-0x3ff10000)/4)*8','(((address-0x3ff10000)%0x2000)/4)*8'),
('IROM-first-page-wrong','p+1024+13*8','p+1024+12*8'),
('IROM-uses-DROM-gate','p+72,16','p+64,16'),
('flash-source-not-copied','em_copy(flash,bytes,size);',''),
('cached-page-is-live-flash-alias','store64(pages+i*8,target+i*65536)','store64(pages+i*8,load64(p)+at)'),
('non-power-of-two-NOR-accepted',' || (size&(size-1))',''),
('close-leaves-stale-views','xt_unmap_pages(load64(s),0x3f400000);xt_unmap_pages(load64(s),0x400d0000);',''),
('unsupported-modes-pretend-success','return -95;','return 0;'),
]
controls=[]
for label,old,new in mutations:
 d=w/label;d.mkdir(exist_ok=True)
 for n in modules:
  text=clone_source(root,n)
  if n=='esp32-cache-emulator.flex':assert old in text,label;text=text.replace(old,new)
  (d/n).write_text(text.replace('"xtensa.flex"',json.dumps(str(source_path(root,'xtensa.flex')))))
 text=source.read_text().replace('"../../emulator/esp32/board.flex"',json.dumps(str(d/'esp32-emulator.flex'))).replace('"../../scripts/lib/host.flex"',json.dumps(str(root/'scripts/lib/host.flex')))
 f=d/'model.flex';f.write_text(text);b=d/'model';checked([compiler,f,'-o',b]);q=run([b,raw]);assert q.returncode==1 and re.fullmatch(rb'Cache case \d+: .+\n',q.stderr),(label,q.returncode,q.stderr)
 controls.append({'control':label,'detected':True,'diagnostic':q.stderr.decode().strip()});print('Cache controls:',len(controls),flush=True)
r={'pass':True,'scope_complete':False,'physical_hardware':False,'checks':checks,'defect_controls':controls,'headers_sha256':headers,'compiler_sha256':sha(compiler),'scope':'Functional PRO DROM/IROM64KiB paging,snapshot/flush,gates,bounds and lifecycle. CPU1 execution,illegal traps,other modes/buses,SPI command engine and full XIP boot remain open.'}
a.report.write_text(json.dumps(r,indent=2)+'\n');print('PASS:',checks,'functional cache checks/',len(controls),'defects')
