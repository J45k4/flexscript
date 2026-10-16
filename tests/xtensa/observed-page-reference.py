#!/usr/bin/env python3
"""Independent GNU bytes/serialized fills and defect checks for page events.

No ESP32 device/driver/compiler encoder imports,hardware access or downloads.
Runs the older strict-page fixture and its independent controls as well.
"""
from emulator_sources import source_path, clone_source
import argparse,hashlib,json,re,struct,subprocess
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__)
for n in ('compiler','work','report'):p.add_argument('--'+n,type=Path,required=True)
p.add_argument('--as',dest='assembler',required=True);p.add_argument('--objcopy',required=True);a=p.parse_args();root=Path(__file__).resolve().parents[2];w=a.work.resolve();w.mkdir(parents=True,exist_ok=True);cc=a.compiler.resolve()
def run(args):return subprocess.run([str(v) for v in args],cwd=root,capture_output=True,timeout=35)
def checked(args):
 q=run(args);assert q.returncode==0,(args,q.stdout,q.stderr);return q
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def assemble(source,label,size):
 obj=w/(label+'.o');raw=w/(label+'.bin');checked([a.assembler,'--text-section-literals',root/source,'-o',obj]);checked([a.objcopy,'-O','binary','--only-section=.text',obj,raw]);assert raw.stat().st_size==size;return raw
raw=assemble('tests/xtensa/observed-page-instructions.S','GNU-observed',12);fills=[0,0x11223344,0xbad00bad,0xffffffff];data=bytearray(struct.pack('<QQ4Q',0x4f42535041474531,12,*fills)+raw.read_bytes()+b'\0'*4)
for fill in fills:
 for offset in range(8):
  for n in range(1,9):data.extend((struct.pack('<I',fill)*4)[offset:offset+n]+b'\0'*(8-n))
assert len(data)==2112;reference=w/'reference.bin';reference.write_bytes(data);fixture=root/'tests/xtensa/observed-pages.flex';binary=w/'model';checked([cc,fixture,'-o',binary]);q=checked([binary,reference]);m=re.fullmatch(rb'Observed CPU pages: (\d+) checks passed\n',q.stdout);assert m;count=int(m[1]);assert count>=10421;print(q.stdout.decode().strip(),flush=True)
prior=assemble('tests/xtensa/paged-instructions.S','GNU-strict',11);old=w/'strict-model';checked([cc,root/'tests/xtensa/pages.flex','-o',old]);q=checked([old,prior]);m=re.fullmatch(rb'CPU pages: (\d+) checks passed\n',q.stdout);assert m;strict=int(m[1]);assert strict==207257
legacy=w/'strict-controls.json';checked(['python3',root/'tests/xtensa/cache-cpu-controls.py','--suite','pages','--compiler',cc,'--instructions',prior,'--work',w/'strict-controls','--report',legacy]);old_report=json.loads(legacy.read_text());assert old_report['pass'] and len(old_report['controls'])==14
names=('xtensa.flex','xtensa-cycle.flex','xtensa-timer.flex','xtensa-window.flex','xtensa-user.flex','xtensa-memory-pages.flex','emulator-memory.flex');sources={n:clone_source(root,n) for n in names}
changes=[
('foreign-event-owner-accepted','xtensa-memory-pages.flex','if owner && owner!=c{return -16;}',''),
('pending-event-reconfigured','xtensa-memory-pages.flex','if load64(d+24) && load64(old){return -16;}',''),
('event-control-alias-accepted','xtensa-memory-pages.flex','if xt_pages_event_alias(c,event,attributes,count){return -22;}',''),
('disabled-fill-byte-order','xtensa-memory-pages.flex','fill>>(((address+i)&3)*8)','fill>>(((3-address-i)&3)*8)'),
('disabled-fetch-uses-data-fill','xtensa-memory-pages.flex','if fill<0 || permission!=1','if fill<0'),
('tail-metadata-is-first-page','xtensa-memory-pages.flex','metadata=load64(attributes+unit*8)','metadata=load64(attributes+first*8)'),
('metadata-OR-loses-first-page','xtensa-memory-pages.flex','store64(event+48,load64(event+48)|metadata);','store64(event+48,metadata);'),
('repeats-ignored','xtensa-memory-pages.flex',' && !(metadata&load64(d+56))',''),
('ack-clears-other-region','xtensa-memory-pages.flex','store64(event,0);store64(event+48,0);xt_pages_update_pending(c);return 0;}','store64(event,0);store64(event+48,0);store64(c+288,0);return 0;}'),
('CPU-close-keeps-event-owner','xtensa.flex','bytes=4096;xt_pages_release_event(c,load64(p+16));','bytes=4096;'),
('unmap-keeps-event-owner','xtensa-memory-pages.flex','xt_pages_release_event(c,load64(p+16));syscall','syscall'),
('read-only-permissions-bypassed','xtensa.flex','if (load64(p+24)&permission)!=permission','if 0'),
('slice-entry-runs-before-pending-event','xtensa.flex','if load64(c+288){store64(run+8,10);return 10;}if limit>fuel','if limit>fuel'),
('load-does-not-yield-before-next-instruction','xtensa.flex','return reason;}if load64(c+288){store64(run+8,10);return 10;}}','return reason;}}'),
]
controls=[]
for label,module,old,new in changes:
 assert old in sources[module],label
 d=w/label;d.mkdir(exist_ok=True)
 for n,s in sources.items():(d/n).write_text(s.replace(old,new) if n==module else s)
 f=d/'model.flex';f.write_text(fixture.read_text().replace('"../../emulator/xtensa/cpu.flex"',json.dumps(str(d/'xtensa.flex'))).replace('"../../scripts/lib/host.flex"',json.dumps(str(root/'scripts/lib/host.flex'))));b=d/'model';checked([cc,f,'-o',b]);q=run([b,reference]);assert q.returncode==1 and re.fullmatch(rb'Observed page case \d+: .+\n',q.stderr),(label,q.returncode,q.stderr)
 controls.append({'control':label,'detected':True,'diagnostic':q.stderr.decode().strip()});print('Observed page controls:',len(controls),flush=True)
r={'pass':True,'scope_complete':False,'ESP32_device_integration':False,'physical_hardware':False,'checks':count,'defect_controls':controls,'strict_page_checks':strict,'strict_page_defect_controls':14,'GNU_instructions_sha256':sha(raw),'serialized_reference_sha256':sha(reference),'compiler_sha256':sha(cc),'source_sha256':{n:hashlib.sha256(s.encode()).hexdigest() for n,s in sources.items()},'scope':'Opt-in opaque metadata,guarded disabled DATA fill,ownership/cross-page validation,bounded summaries andCPU reschedule beforefollowing instruction. Default strict memory remains. ESP32 cache integration/IRQ/fill/fault hardware fidelity remains open.'};a.report.write_text(json.dumps(r,indent=2)+'\n');print('PASS:',count,'observed checks/',len(controls),'controls;strict',strict,'/14')
