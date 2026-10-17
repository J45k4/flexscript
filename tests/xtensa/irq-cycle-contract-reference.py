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
checked([a.assembler,root/'tests/xtensa/irq-cycle-contract.S','-o',obj]);checked([a.objcopy,'-O','binary','--only-section=.text',obj,raw]);assert raw.stat().st_size==777
fixture=root/'tests/xtensa/irq-cycle-contract.flex';binary=work/'model';checked([a.compiler.resolve(),fixture,'-o',binary]);q=checked([binary,raw]);match=re.fullmatch(rb'IRQ cycle: (\d+) checks passed\n',q.stdout);assert match and int(match[1])>=50
checks=int(match[1]);print(q.stdout.decode().strip(),flush=True)
original={name:clone_source(root,name) for name in ('xtensa.flex','xtensa-cycle.flex','esp32-emulator.flex')}
mutations=[('IRQ-entry-too-short', 'xtensa-cycle.flex', 'xt_cycle_now(c)+7', 'xt_cycle_now(c)+6'), ('IRQ-entry-omitted', 'xtensa-cycle.flex', 'if !load64(c+328){return 0;}store64(c+392,', 'if 1{return 0;}store64(c+392,'), ('INTSET-phase-omitted', 'xtensa-cycle.flex', 'return pending&~128;', 'return pending;'), ('INTSET-phase-too-long', 'xtensa-cycle.flex', 'store64(c+400,now+2);', 'store64(c+400,now+3);'), ('INTSET-reassert-postpones', 'xtensa-cycle.flex', ' && !prior_irq &&', ' &&'), ('INTCLEAR-keeps-stale-phase', 'xtensa.flex', 'if value&128{store64(c+400,0);}', ''), ('source-profile-discarded', 'xtensa-cycle.flex', ' || (load64(c+400)>now && (xt_sr(c,226)&128))', ''), ('RFE-redirect-omitted', 'xtensa.flex', 'op==0x003000{transfer=1;', 'op==0x003000{'), ('IRQ-entry-retires-instruction', 'xtensa-cycle.flex', 'store64(c+392,xt_cycle_now(c)+7);', 'store64(c+176,load64(c+176)+1);store64(c+392,xt_cycle_now(c)+7);'), ('IRQ-entry-clock-not-advanced', 'esp32-emulator.flex', 'se_clock_idle_cycles(s,wait);', 'se_clock_idle_cycles(s,0);'), ('IRQ-clock-double-counted', 'esp32-emulator.flex', 'let result=se_clock_idle_cycles(s,wait);', 'let result=se_clock_idle_cycles(s,wait);xt_wsr(cpu,234,xt_sr(cpu,234)+wait);'), ('IRQ-deadline-uses-CCOUNT', 'xtensa-cycle.flex', 'return load64(c+176)+load64(c+336);', 'return xt_sr(c,234);')]
for label,name,old,new in mutations:assert original[name].count(old)==1,(label,original[name].count(old))
def one(item):
 label,name,old,new=item;directory=work/label;directory.mkdir(exist_ok=True)
 for filename,text in original.items():
  if filename==name:text=text.replace(old,new,1)
  text=re.sub(r'^import "([^"]+)";',lambda m:'import '+json.dumps(str(directory/m[1] if m[1] in original else source_path(root,m[1])))+';',text,flags=re.M)
  (directory/filename).write_text(text)
 source=directory/'model.flex';source.write_text(fixture.read_text().replace('"../../emulator/esp32/board.flex"',json.dumps(str(directory/'esp32-emulator.flex'))).replace('"../../scripts/lib/host.flex"',json.dumps(str(root/'scripts/lib/host.flex'))))
 binary=directory/'model';checked([a.compiler.resolve(),source,'-o',binary]);q=run([binary,raw]);(directory/'stdout').write_bytes(q.stdout);(directory/'stderr').write_bytes(q.stderr)
 assert q.returncode==1 and re.fullmatch(rb'IRQ cycle case \d+: .+\n',q.stderr),(label,q.returncode,q.stdout,q.stderr)
 print('IRQ cycle control:',label,'detected',flush=True)
 return {'control':label,'detected':True,'diagnostic':q.stderr.decode().strip()}
with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:controls=list(pool.map(one,mutations))
report={'pass':True,'checks':checks,'defect_controls':controls,'physical_hardware_accessed':False,'scope_complete':False,'GNU_fixture_sha256':sha(raw),'compiler_sha256':sha(a.compiler),'source_sha256':{str(p.relative_to(root)):sha(p) for p in [fixture,root/'tests/xtensa/irq-cycle-contract.S',Path(__file__),*[source_path(root,n) for n in original]]},'limits':'Measured IRQ7 source,level1 entry and RFE component. Full comparator pending state,higher levels,exceptions,CPU1 and pipeline remain open.'}
a.report.write_text(json.dumps(report,indent=2)+'\n');print(f'PASS:{checks} CPU-cycle event checks/{len(controls)} defect controls',flush=True)
