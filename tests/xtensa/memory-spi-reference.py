#!/usr/bin/env python3
"""SDK-addressed SPI0/SPI1/NOR tests and GNU SRC defect controls.

Explicit compiler,already downloaded hash-pinned primary sources and GNU
fixture only. No firmware-driver import,network or hardware access.
"""
from emulator_sources import source_path, clone_source
import argparse,hashlib,json,re,shutil,subprocess
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__)
for n in ('compiler','reference','instructions','work','report'):p.add_argument('--'+n,type=Path,required=True)
p.add_argument('--cc',default='cc');a=p.parse_args();root=Path(__file__).resolve().parents[2];w=a.work.resolve();w.mkdir(exist_ok=True,parents=True);compiler=a.compiler.resolve();refs=a.reference.resolve();raw=a.instructions.resolve()
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
headers={}
for row in json.loads((root/'tests/xtensa/memory-spi-oracle/sources.json').read_text()):
 assert sha(refs/row['name'])==row['sha256'],row['name'];headers[row['name']]=row['sha256']
def run(args):return subprocess.run([str(x) for x in args],cwd=root,capture_output=True,timeout=45)
def checked(args):
 q=run(args);assert q.returncode==0,(args,q.stdout,q.stderr);return q
inc=w/'include';(inc/'soc').mkdir(exist_ok=True,parents=True)
for original,name in [('sdk-spi-reg.h','spi_reg.h'),('sdk-efuse-reg.h','efuse_reg.h'),('sdk-efuse-defs.h','soc/efuse_defs.h'),('sdk-gpio-sd-reg.h','gpio_sd_reg.h'),('soc-reg-base.h','reg_base.h')]:shutil.copyfile(refs/original,inc/name)
c=w/'C-reference';meta=w/'reference.bin';checked([a.cc,'-std=gnu11','-O2','-Wall','-Wextra','-Werror','-I'+str(root/'tests/esp32/i2s-oracle'),'-I'+str(inc),root/'tests/xtensa/memory-spi-oracle/reference.c','-o',c]);meta.write_bytes(checked([c]).stdout);assert meta.stat().st_size==360
modules=('esp32-emulator.flex','esp32-cache-emulator.flex','esp32-clock-emulator.flex','esp32-gpio-emulator.flex','esp32-gpio-pads.flex','esp32-spi-emulator.flex','esp32-rmt-emulator.flex','esp32-i2c-emulator.flex','esp32-i2s-emulator.flex','xtensa.flex','xtensa-cycle.flex','xtensa-timer.flex','xtensa-window.flex','xtensa-user.flex','xtensa-memory-pages.flex','emulator-memory.flex')
sources={n:clone_source(root,n) for n in modules}
counts={}
for name,fixture,argument in [('memory_spi','memory-spi-model.flex',meta),('src','src.flex',raw)]:
 binary=w/name;checked([compiler,root/'tests/xtensa'/fixture,'-o',binary]);q=checked([binary,argument]);match=re.fullmatch(rb'(?:Memory SPI|SRC): (\d+) checks passed\n',q.stdout);assert match,q.stdout;counts[name]=int(match[1])
mutations=[
('hardware-READ-uses-QEMU-MISO-length','esp32-cache-emulator.flex','rx=(load64(r+8)>>24)&255;','rx=((load64(r+0x2c*2)&0xffffff)+8)/8;','memory_spi'),
('unsupported-cache-opcode-published','esp32-cache-emulator.flex','if enabled{let mode=se_flash_cache_mode(s);if mode{return mode;}}','','memory_spi'),
('SPI-enable-rollback-missing','esp32-cache-emulator.flex','store64(r+offset*2,old);se_cache_publish(s);return result;','se_cache_publish(s);return result;','memory_spi'),
('SRC-SAR-truncated','xtensa.flex','let shift=xt_sr(c,3)&63;','let shift=xt_sr(c,3)&31;','src'),
('SRC-wrong-source-order','xtensa.flex','let value=right;if shift==32{value=left;}','let swap=left;left=right;right=swap;let value=right;if shift==32{value=left;}','src'),
('SRC-signed-right-shift','xtensa.flex','value=(right>>shift)|(left<<(32-shift));','value=(xt_signed(right)>>shift)|(left<<(32-shift));','src'),
('SRC-zero-shift-is-high','xtensa.flex','let value=right;if shift==32','let value=left;if shift==32','src'),
('SRC-large-shift-zero','xtensa.flex','value=left>>(shift-32);','value=0;','src'),
('SRC-window-check-missing','xtensa-window.flex','high==0x81 || ','','src'),
('CMD-busy-clears-early','esp32-cache-emulator.flex','return load64(t);}if offset==0xf8','return 0;}if offset==0xf8','memory_spi'),
('command-completes-before-deadline','esp32-cache-emulator.flex','load64(t+8)<=load64(s+16)','load64(t+8)-1<=load64(s+16)','memory_spi'),
('wrong-JEDEC','esp32-cache-emulator.flex','0x2085|(density<<16)','0x40ef|(density<<16)','memory_spi'),
('shared-NOR-arbitration-missing','esp32-cache-emulator.flex','if load64(p+192) || load64(p+320){return -16;}','if load64(t){return -16;}','memory_spi'),
('wrong-USR-address','esp32-cache-emulator.flex','address=load64(r+8)>>8;','address=load64(r+8)&0xffffff;','memory_spi'),
('wrong-hardware-READ-address','esp32-cache-emulator.flex','address=load64(r+8)&0xffffff;rx=','address=load64(r+8)>>8;rx=','memory_spi'),
('FIFO-byte-order-reversed','esp32-cache-emulator.flex','let shift=(index&3)*8;','let shift=(3-(index&3))*8;','memory_spi'),
('WREN-does-not-latch','esp32-cache-emulator.flex','if op==6{store64(p+136,1);}','if op==6{store64(p+136,0);}','memory_spi'),
('program-needs-no-WEL','esp32-cache-emulator.flex','if !load64(p+136){return -13;}','','memory_spi'),
('program-escapes-write-window','esp32-cache-emulator.flex','!se_flash_writable(p,address,tx)','0','memory_spi'),
('program-can-set-NOR-bits','esp32-cache-emulator.flex','load8(data+at)&load8(t+64+i)','load8(data+at)|load8(t+64+i)','memory_spi'),
('page-crossing-accepted','esp32-cache-emulator.flex',' || (address&255)+tx>256','','memory_spi'),
('WIP-missing-after-program','esp32-cache-emulator.flex','store64(p+176,now+4096);','store64(p+176,0);','memory_spi'),
('erase-wrong-length','esp32-cache-emulator.flex','while i<4096{store8(data+address+i,255);','while i<4095{store8(data+address+i,255);','memory_spi'),
('source-NOR-not-copied','esp32-cache-emulator.flex','em_copy(flash,bytes,size);','','memory_spi'),
('SPI-request-gate-ignored','esp32-cache-emulator.flex','enabled=enabled && (load64(p+36864+0x50*2)&1)','enabled=enabled && 1','memory_spi'),
('divider-ignored','esp32-cache-emulator.flex','bits*factor*se_apb_factor(s)','bits*se_apb_factor(s)','memory_spi'),
('APB-guard-missing','esp32-clock-emulator.flex','if se_flash_pending(s){return 1;}','','memory_spi'),
('eFuse-snapshot-not-copied','esp32-cache-emulator.flex','em_copy(p+1536,bytes,28);','','memory_spi'),
('eFuse-write-accepted','esp32-cache-emulator.flex','if writing{return -13;}return em_u32(p+1536','if writing{return 0;}return em_u32(p+1536','memory_spi'),
('trace-address-wrong','esp32-cache-emulator.flex','store64(trace+16,address);','store64(trace+16,address+1);','memory_spi'),
('volatile-status-drops-SR2','esp32-cache-emulator.flex','value=value|(load64(p+128)&0xff00);','value=value;','memory_spi'),
]
controls=[]
for label,module,old,new,suite in mutations:
 assert old in sources[module],label
 d=w/label;d.mkdir(exist_ok=True)
 for n,text in sources.items():(d/n).write_text(text.replace(old,new) if n==module else text)
 fixture='src.flex' if suite=='src' else 'memory-spi-model.flex';text=(root/'tests/xtensa'/fixture).read_text().replace('"../../lib/','"'+str(d)+'/').replace('"../../scripts/lib/host.flex"',json.dumps(str(root/'scripts/lib/host.flex')));f=d/'test.flex';f.write_text(text);binary=d/'test';checked([compiler,f,'-o',binary]);q=run([binary,raw if suite=='src' else meta]);assert q.returncode==1 and re.search(rb'(?:SRC|Memory SPI) case \d+:',q.stderr),(label,q.returncode,q.stderr)
 controls.append({'control':label,'suite':suite,'detected':True,'diagnostic':q.stderr.decode().strip()});print('Memory SPI/SRC controls:',len(controls),flush=True)
r={'pass':True,'scope_complete':False,'physical_hardware':False,'checks':counts,'controls':controls,'compiler_sha256':sha(compiler),'GNU_SRC_sha256':sha(raw),'SDK_metadata_sha256':sha(meta),'reference_sha256':headers,'source_sha256':{n:hashlib.sha256(s.encode()).hexdigest() for n,s in sources.items()},'scope':'Functional single-wire original SPI0/1 command deadlines,shared NOR,read-only/default bounded writes,volatile status,cache request gate,read-only eFuse block0 and SRC. Full waveform/timing,multiline/encryption/PSRAM and all-cache parity remain open.'}
a.report.write_text(json.dumps(r,indent=2)+'\n');print('PASS:',counts,'and',len(controls),'defect controls')
