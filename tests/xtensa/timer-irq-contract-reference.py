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
checked([a.assembler,root/'tests/xtensa/timer-irq-contract.S','-o',obj]);checked([a.objcopy,'-O','binary','--only-section=.text',obj,raw]);assert raw.stat().st_size==838
fixture=root/'tests/xtensa/timer-irq-contract.flex';binary=work/'model';checked([a.compiler.resolve(),fixture,'-o',binary]);q=checked([binary,raw]);match=re.fullmatch(rb'Timer IRQ: (\d+) checks passed\n',q.stdout);assert match and int(match[1])>=50
checks=int(match[1]);print(q.stdout.decode().strip(),flush=True)
original={name:clone_source(root,name) for name in ('xtensa.flex','xtensa-cycle.flex','xtensa-timer.flex','esp32-emulator.flex')}
mutations=[('priority-not-highest', 'xtensa.flex', 'if pending&xt_irq_mask(level){return level;}', 'if pending&xt_irq_mask(level){return 1;}'), ('EXCM-floor-too-low', 'xtensa.flex', 'if load64(c+408){floor=3;}', 'if load64(c+408){floor=1;}'), ('high-entry-level-not-set', 'xtensa.flex', '(ps&~15)|16|level', 'ps|16'), ('EPS-save-wrong-bank', 'xtensa.flex', 'xt_wsr(c,192+level,ps);', 'xt_wsr(c,193,ps);'), ('RFI-PS-not-restored', 'xtensa.flex', 'xt_wsr(c,230,xt_sr(c,192+level));', 'xt_wsr(c,230,0);'), ('EPC-save-wrong-bank', 'xtensa.flex', 'xt_wsr(c,176+level,load64(c+128));', 'xt_wsr(c,177,load64(c+128));'), ('high-entry-phase-omitted', 'xtensa.flex', 'if xt_cycle_irq(c){return 13;}', 'if level==1 && xt_cycle_irq(c){return 13;}'), ('RFI-pending-overlap-omitted', 'xtensa.flex', 'if load64(c+328){store64(c+440,1);}', ''), ('timer-WAITI-deadline-omitted', 'esp32-emulator.flex', 'let timer=xt_timer_next(load64(s));', 'let timer= -1;'), ('WAITI-ignores-high-priority', 'esp32-emulator.flex', 'return xt_irq_level(load64(s))!=0;', 'let cpu=load64(s);return (xt_sr(cpu,226)&xt_sr(cpu,228)&0x82) && !(xt_sr(cpu,230)&31);'), ('timer-deadline-ignores-enable', 'xtensa-timer.flex', '(enabled&bit) && level>current', 'level>current'), ('timer-deadline-ignores-level', 'xtensa-timer.flex', '(enabled&bit) && level>current', '(enabled&bit)')]
mutations += [('pending-WAITI-phase-omitted','esp32-emulator.flex','if se_clock_idle_cycles(s,3){return -1;}','if se_clock_idle_cycles(s,0){return -1;}'),('pending-WAITI-eligibility-not-recorded','xtensa.flex','store64(c+488,xt_irq_level(c)!=0);','store64(c+488,0);'),('pending-WAITI-phase-not-consumed','esp32-emulator.flex','store64(cpu+488,0);store64(s+208,0);','store64(s+208,0);')]
for label,name,old,new in mutations:assert original[name].count(old)==1,(label,original[name].count(old))
def one(item):
 label,name,old,new=item;directory=work/label;directory.mkdir(exist_ok=True)
 for filename,text in original.items():
  if filename==name:text=text.replace(old,new,1)
  text=re.sub(r'^import "([^"]+)";',lambda m:'import '+json.dumps(str(directory/m[1] if m[1] in original else source_path(root,m[1])))+';',text,flags=re.M)
  (directory/filename).write_text(text)
 source=directory/'model.flex';source.write_text(fixture.read_text().replace('"../../emulator/esp32/board.flex"',json.dumps(str(directory/'esp32-emulator.flex'))).replace('"../../scripts/lib/host.flex"',json.dumps(str(root/'scripts/lib/host.flex'))))
 binary=directory/'model';checked([a.compiler.resolve(),source,'-o',binary]);q=run([binary,raw]);(directory/'stdout').write_bytes(q.stdout);(directory/'stderr').write_bytes(q.stderr)
 assert q.returncode==1 and re.fullmatch(rb'Timer IRQ case \d+: .+\n',q.stderr),(label,q.returncode,q.stdout,q.stderr)
 print('Timer IRQ control:',label,'detected',flush=True)
 return {'control':label,'detected':True,'diagnostic':q.stderr.decode().strip()}
with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:controls=list(pool.map(one,mutations))
report={'pass':True,'checks':checks,'defect_controls':controls,'physical_hardware_accessed':False,'scope_complete':False,'GNU_fixture_sha256':sha(raw),'compiler_sha256':sha(a.compiler),'source_sha256':{str(p.relative_to(root)):sha(p) for p in [fixture,root/'tests/xtensa/timer-irq-contract.S',Path(__file__),*[source_path(root,n) for n in original]]},'limits':'Measured IRQ7 source,level1 entry and RFE component. Natural expiry recognition,ISR body timing,CPU1,NMI/debug and general pipeline remain open.'}
a.report.write_text(json.dumps(report,indent=2)+'\n');print(f'PASS:{checks} timer priority/event checks/{len(controls)} defect controls',flush=True)
