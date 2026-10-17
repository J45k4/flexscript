#!/usr/bin/env python3
"""Comparator state contracts and deliberately broken implementations. GNU silicon captures are replayed separately."""
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
fixture=root/'tests/xtensa/ccompare-contract.flex';binary=work/'model';checked([a.compiler.resolve(),fixture,'-o',binary]);q=checked([binary]);match=re.fullmatch(rb'Comparator: (\d+) checks passed\n',q.stdout);assert match
checks=int(match[1]);print(q.stdout.decode().strip(),flush=True)
original={name:clone_source(root,name) for name in ('xtensa.flex','xtensa-timer.flex','esp32-clock-emulator.flex','esp32-emulator.flex')}

mutations=[('initial-equality-missing', 'xtensa-timer.flex', 'if enabled{xt_timer_equal(c,xt_timer_count(c));}', ''), ('INTCLEAR-clears-timer', 'xtensa.flex', 'if index==227{', 'if index==227{store64(c+416,load64(c+416)&~value);'), ('compare-write-not-acknowledged', 'xtensa.flex', 'store64(c+416,load64(c+416)&~xt_timer_mask(index-240));', ''), ('wrong-timer1-line', 'xtensa-timer.flex', 'if index==1{return 32768;}', 'if index==1{return 128;}'), ('equality-write-ignored', 'xtensa.flex', 'xt_timer_equal(c,value);', ''), ('guest-write-crosses-skipped-values', 'xtensa.flex', 'store64(c+432,value);xt_timer_equal(c,value);', 'xt_timer_interval(c,load64(c+432),(value-load64(c+432))&0xffffffff);store64(c+432,value);xt_timer_equal(c,value);'), ('zero-distance-is-immediate', 'xtensa-timer.flex', 'if !distance{distance=0x100000000;}if cycles>=distance{', 'if cycles>=distance{'), ('retirement-sync-missing', 'xtensa-timer.flex', 'xt_timer_interval(c,load64(c+432),delta);', ''), ('elapsed-clock-is-guest-write', 'esp32-clock-emulator.flex', 'xt_ccount_advance(cpu,cycles);', 'xt_wsr(cpu,234,cc+cycles);'), ('past-target-not-crossed', 'xtensa-timer.flex', 'if cycles>=distance{', 'if cycles==distance{'), ('active-config-discarded', 'xtensa-timer.flex', 'if load64(c+416){return -16;}', '')]
for label,name,old,new in mutations:assert original[name].count(old)==1,(label,original[name].count(old))
def one(item):
 label,name,old,new=item;directory=work/label;directory.mkdir(exist_ok=True)
 for filename,text in original.items():
  if filename==name:text=text.replace(old,new,1)
  text=re.sub(r'^import "([^"]+)";',lambda m:'import '+json.dumps(str(directory/m[1] if m[1] in original else source_path(root,m[1])))+';',text,flags=re.M)
  (directory/filename).write_text(text)
 source=directory/'model.flex';source.write_text(fixture.read_text().replace('"../../emulator/esp32/board.flex"',json.dumps(str(directory/'esp32-emulator.flex'))).replace('"../../scripts/lib/host.flex"',json.dumps(str(root/'scripts/lib/host.flex'))))
 binary=directory/'model';checked([a.compiler.resolve(),source,'-o',binary]);q=run([binary]);(directory/'stdout').write_bytes(q.stdout);(directory/'stderr').write_bytes(q.stderr)
 assert q.returncode==1 and re.fullmatch(rb'Comparator case \d+: .+\n',q.stderr),(label,q.returncode,q.stdout,q.stderr)
 print('Comparator control:',label,'detected',flush=True)
 return {'control':label,'detected':True,'diagnostic':q.stderr.decode().strip()}
with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:controls=list(pool.map(one,mutations))
report={'pass':True,'checks':checks,'defect_controls':controls,'physical_hardware_accessed':False,'scope_complete':False,'GNU_fixture_sha256':None,'compiler_sha256':sha(a.compiler),'source_sha256':{str(p.relative_to(root)):sha(p) for p in [fixture,Path(__file__),*[source_path(root,n) for n in original]]},'limits':'Raw comparator pending state and elapsed counter progression. Priority delivery,WAITI deadlines and CCOMPARE suffix timing remain open.'}
a.report.write_text(json.dumps(report,indent=2)+'\n');print(f'PASS:{checks} comparator state checks/{len(controls)} defect controls',flush=True)
