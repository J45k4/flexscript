#!/usr/bin/env python3
"""GNU-backed CPU timing event contracts and deliberately broken implementations."""
from emulator_sources import source_path, clone_source
import argparse, concurrent.futures, hashlib, json, re, subprocess
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__)
for name in ('compiler','work','report'):p.add_argument('--'+name,type=Path,required=True)
p.add_argument('--as',dest='assembler',required=True);p.add_argument('--objcopy',required=True)
a=p.parse_args();root=Path(__file__).resolve().parents[2];work=a.work.resolve();work.mkdir(parents=True,exist_ok=True)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def run(cmd):return subprocess.run([str(x) for x in cmd],cwd=root,capture_output=True,timeout=90)
def checked(cmd):
 q=run(cmd);assert q.returncode==0,(cmd,q.returncode,q.stdout[-2000:],q.stderr[-2000:]);return q
obj=work/'GNU-cycle.o';raw=work/'GNU-cycle.bin'
checked([a.assembler,root/'tests/xtensa/cycle-contract.S','-o',obj]);checked([a.objcopy,'-O','binary','--only-section=.text',obj,raw]);assert raw.stat().st_size==1027
fixture=root/'tests/xtensa/cycle-contract.flex';binary=work/'model';checked([a.compiler.resolve(),fixture,'-o',binary]);q=checked([binary,raw]);match=re.fullmatch(rb'Cycle: (\d+) checks passed\n',q.stdout);assert match and int(match[1])>=50
checks=int(match[1]);print(q.stdout.decode().strip(),flush=True)
original={name:clone_source(root,name) for name in ('xtensa.flex','xtensa-cycle.flex','esp32-emulator.flex')}
mutations=[
 ('board-stall-clock-not-advanced','esp32-emulator.flex','se_clock_idle_cycles(s,wait);','se_clock_idle_cycles(s,0);'),
 ('board-stall-counter-double-counted','esp32-emulator.flex','let result=se_clock_idle_cycles(s,wait);','let result=se_clock_idle_cycles(s,wait);xt_wsr(cpu,234,xt_sr(cpu,234)+wait);'),
 ('board-stall-retires-extra-instructions','esp32-emulator.flex','let result=se_clock_idle_cycles(s,wait);','let result=se_clock_idle_cycles(s,wait);store64(cpu+176,load64(cpu+176)+wait);'),
 ('board-stall-clock-not-published','esp32-emulator.flex','if xt_cycle_clock(cpu,load64(se_clock(s)+152)) || xt_cycle_ack(cpu)','if xt_cycle_ack(cpu)'),
 ('PS-readiness-too-short','xtensa-cycle.flex','store64(c+344,now+5);','store64(c+344,now+4);'),
 ('PS-reader-dependency-ignored','xtensa-cycle.flex','if load64(c+344)>ready{ready=load64(c+344);}','if 0{ready=load64(c+344);}'),
 ('SAR-fence-dependency-ignored','xtensa-cycle.flex','op==0x002010 && load64(c+352)-1>ready','0 && load64(c+352)-1>ready'),
 ('PS-RSYNC-over-serializes','xtensa-cycle.flex','if op==0x002010 && load64(c+352)-1>ready{ready=load64(c+352)-1;}','if op==0x002010{if load64(c+344)-1>ready{ready=load64(c+344)-1;}if load64(c+352)-1>ready{ready=load64(c+352)-1;}}'),
 ('RSIL-spacing-ignored','xtensa-cycle.flex','if (op&0xfff00f)==0x006000 && load64(c+360)>ready','if 0 && load64(c+360)>ready'),
 ('event-advances-PC','xtensa-cycle.flex','store64(c+368,ready);','store64(c+128,load64(c+128)+3);store64(c+368,ready);'),
 ('event-retires-instruction','xtensa-cycle.flex','store64(c+368,ready);','store64(c+176,load64(c+176)+1);store64(c+368,ready);'),
 ('event-consumes-hardware-loop','xtensa-cycle.flex','store64(c+368,ready);','xt_wsr(c,2,0);store64(c+368,ready);'),
 ('pending-step-executes','xtensa.flex','if load64(c+368){return 13;}',''),
 ('pending-run-executes','xtensa.flex','if load64(c+368){store64(run+8,13);return 13;}',''),
 ('early-ack-accepted','xtensa-cycle.flex','if xt_cycle_wait(c){return -11;}',''),
 ('ack-advances-PC','xtensa-cycle.flex','store64(c+368,0);store64(c+376,0);','store64(c+128,load64(c+128)+3);store64(c+368,0);store64(c+376,0);'),
 ('ack-keeps-event-pending','xtensa-cycle.flex','store64(c+368,0);store64(c+376,0);',''),
 ('clock-rewind-accepted','xtensa-cycle.flex',' || idle<load64(c+336)',''),
 ('readiness-uses-writable-CCOUNT','xtensa-cycle.flex','return load64(c+176)+load64(c+336);','return xt_sr(c,234);'),
 ('pending-profile-overwritten','xtensa-cycle.flex',' || load64(c+368){return -16;}','{return -16;}'),
 ('retirement-timestamp-off-by-one','xtensa.flex','xt_cycle_retire(c,op,length,next,transfer,prior_irq);store64(c+128,xt_loop_next(c,next,loop_ok));store64(c+176,load64(c+176)+1);','store64(c+128,xt_loop_next(c,next,loop_ok));store64(c+176,load64(c+176)+1);xt_cycle_retire(c,op,length,next,transfer,prior_irq);'),
 ('generic-profile-enabled','xtensa.flex','em_zero(c,4096);let table=alloc(1024);','em_zero(c,4096);store64(c+328,1);let table=alloc(1024);'),
 ('original-board-profile-disabled','esp32-emulator.flex','xt_cycle_profile(cpu,1);','xt_cycle_profile(cpu,0);'),
 ('S3-inherits-LX6-profile','esp32-emulator.flex','if !chip{se_clock_profile(s,0);xt_cycle_profile(cpu,1);xt_timer_config(cpu,1);}return s;','if !chip{se_clock_profile(s,0);xt_timer_config(cpu,1);}xt_cycle_profile(cpu,1);return s;'),
]
for label,name,old,new in mutations:assert original[name].count(old)==1,(label,original[name].count(old))
def one(item):
 label,name,old,new=item;directory=work/label;directory.mkdir(exist_ok=True)
 for filename,text in original.items():
  if filename==name:text=text.replace(old,new,1)
  text=re.sub(r'^import "([^"]+)";',lambda m:'import '+json.dumps(str(directory/m[1] if m[1] in original else source_path(root,m[1])))+';',text,flags=re.M)
  (directory/filename).write_text(text)
 source=directory/'model.flex';source.write_text(fixture.read_text().replace('"../../emulator/esp32/board.flex"',json.dumps(str(directory/'esp32-emulator.flex'))).replace('"../../scripts/lib/host.flex"',json.dumps(str(root/'scripts/lib/host.flex'))))
 binary=directory/'model';checked([a.compiler.resolve(),source,'-o',binary]);q=run([binary,raw]);(directory/'stdout').write_bytes(q.stdout);(directory/'stderr').write_bytes(q.stderr)
 assert q.returncode==1 and re.fullmatch(rb'Cycle case \d+: .+\n',q.stderr),(label,q.returncode,q.stdout,q.stderr)
 print('Cycle control:',label,'detected',flush=True)
 return {'control':label,'detected':True,'diagnostic':q.stderr.decode().strip()}
with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:controls=list(pool.map(one,mutations))
report={'pass':True,'checks':checks,'defect_controls':controls,'physical_hardware_accessed':False,'scope_complete':False,'GNU_fixture_sha256':sha(raw),'compiler_sha256':sha(a.compiler),'source_sha256':{str(p.relative_to(root)):sha(p) for p in [fixture,root/'tests/xtensa/cycle-contract.S',Path(__file__),*[source_path(root,n) for n in original]]},'limits':'Partial measured LX6 overlap and event ownership. Full CPI, pending IRQ phase and frontend/cache timing remain open.'}
a.report.write_text(json.dumps(report,indent=2)+'\n');print(f'PASS:{checks} CPU-cycle event checks/{len(controls)} defect controls',flush=True)
