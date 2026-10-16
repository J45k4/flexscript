#!/usr/bin/env python3
"""GNU-backed frontend transfer contracts and independent defect controls."""
from emulator_sources import source_path, clone_source
import argparse,concurrent.futures,hashlib,json,re,subprocess
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__)
for name in ('compiler','work','report'):p.add_argument('--'+name,type=Path,required=True)
p.add_argument('--as',dest='assembler',required=True);p.add_argument('--objcopy',required=True)
a=p.parse_args();root=Path(__file__).resolve().parents[2];work=a.work.resolve();work.mkdir(parents=True,exist_ok=True);sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def run(cmd):return subprocess.run([str(x) for x in cmd],cwd=root,capture_output=True,timeout=90)
def checked(cmd):
 q=run(cmd);assert q.returncode==0,(cmd,q.returncode,q.stdout[-1500:],q.stderr[-2000:]);return q
obj=work/'GNU-branch.o';raw=work/'GNU-branch.bin';checked([a.assembler,root/'tests/xtensa/branch-cycle-contract.S','-o',obj]);checked([a.objcopy,'-O','binary','--only-section=.text',obj,raw]);assert raw.stat().st_size==771
fixture=root/'tests/xtensa/branch-cycle-contract.flex';binary=work/'model';checked([a.compiler.resolve(),fixture,'-o',binary]);q=checked([binary,raw]);match=re.fullmatch(rb'Branch cycles: (\d+) checks passed\n',q.stdout);assert match and int(match[1])>=800;checks=int(match[1]);print(q.stdout.decode().strip(),flush=True)
original={n:clone_source(root,n) for n in ('xtensa.flex','xtensa-cycle.flex','esp32-emulator.flex')}
mutations=[
 ('frontend-delay-ignored','xtensa.flex','if !level && xt_cycle_fetch(c){return 13;}',''),
 ('target-alignment-ignored','xtensa-cycle.flex','now+4+((next>>1)&1)','now+4'),
 ('wrong-target-alignment-bit','xtensa-cycle.flex','now+4+((next>>1)&1)','now+4+(next&1)'),
 ('branch-base-cost-too-short','xtensa-cycle.flex','now+4+((next>>1)&1)','now+3+((next>>1)&1)'),
 ('J-to-next-treated-as-fallthrough','xtensa-cycle.flex','if transfer{store64(c+384,','if transfer && next!=load64(c+128)+length{store64(c+384,'),
 ('untaken-path-charged','xtensa.flex','if take{transfer=1;loop_ok=0;let delta=op>>12;','transfer=1;if take{transfer=1;loop_ok=0;let delta=op>>12;'),
 ('direct-J-not-charged','xtensa.flex','else if (op&63)==6{transfer=1;','else if (op&63)==6{transfer=0;'),
 ('direct-call-not-charged','xtensa.flex','else if low==5{transfer=1;','else if low==5{transfer=0;'),
 ('indirect-call-not-charged','xtensa.flex','else if (op&0xfff0cf)==0x0000c0{transfer=1;','else if (op&0xfff0cf)==0x0000c0{transfer=0;'),
 ('regular-return-not-charged','xtensa.flex','else if op==0x000080{transfer=1;','else if op==0x000080{transfer=0;'),
 ('density-return-not-charged','xtensa.flex','else if op==0xf00d{transfer=1;','else if op==0xf00d{transfer=0;'),
 ('active-frontend-profile-discarded','xtensa-cycle.flex',' || load64(c+384)>now',''),
 ('frontend-wait-retires-early','xtensa-cycle.flex','store64(c+368,fetch_ready);','store64(c+176,load64(c+176)+1);store64(c+368,fetch_ready);'),
 ('frontend-wait-skips-target','xtensa-cycle.flex','store64(c+368,fetch_ready);','store64(c+128,load64(c+128)+3);store64(c+368,fetch_ready);'),
 ('frontend-uses-writable-counter','xtensa-cycle.flex','return load64(c+176)+load64(c+336);','return xt_sr(c,234);'),
 ('fetch-fault-before-frontend-ready','xtensa-cycle.flex','store64(c+368,fetch_ready);','if !xt_pointer(c,load64(c+128),1,5){xt_fault(c,-14,load64(c+128));}store64(c+368,fetch_ready);'),
 ('board-stall-clock-not-advanced','esp32-emulator.flex','se_clock_idle_cycles(s,wait);','se_clock_idle_cycles(s,0);'),
 ('board-stall-counter-double-counted','esp32-emulator.flex','let result=se_clock_idle_cycles(s,wait);','let result=se_clock_idle_cycles(s,wait);xt_wsr(cpu,234,xt_sr(cpu,234)+wait);'),
]
for label,name,old,new in mutations:assert original[name].count(old)==1,(label,original[name].count(old))
def one(item):
 label,name,old,new=item;dest=work/label;dest.mkdir(exist_ok=True)
 for filename,text in original.items():
  if filename==name:text=text.replace(old,new,1)
  text=re.sub(r'^import "([^"]+)";',lambda m:'import '+json.dumps(str(dest/m[1] if m[1] in original else source_path(root,m[1])))+';',text,flags=re.M);(dest/filename).write_text(text)
 source=dest/'model.flex';source.write_text(fixture.read_text().replace('"../../emulator/esp32/board.flex"',json.dumps(str(dest/'esp32-emulator.flex'))).replace('"../../scripts/lib/host.flex"',json.dumps(str(root/'scripts/lib/host.flex'))));binary=dest/'model';checked([a.compiler.resolve(),source,'-o',binary]);q=run([binary,raw]);(dest/'stdout').write_bytes(q.stdout);(dest/'stderr').write_bytes(q.stderr)
 assert q.returncode==1 and re.fullmatch(rb'Branch cycle case \d+: .+\n',q.stderr),(label,q.returncode,q.stdout,q.stderr)
 print('Branch control:',label,'detected',flush=True);return {'control':label,'detected':True,'diagnostic':q.stderr.decode().strip()}
with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:controls=list(pool.map(one,mutations))
a.report.write_text(json.dumps({'pass':True,'checks':checks,'defect_controls':controls,'physical_hardware_accessed':False,'scope_complete':False,'GNU_fixture_sha256':sha(raw),'compiler_sha256':sha(a.compiler),'source_sha256':{str(p.relative_to(root)):sha(p) for p in [fixture,root/'tests/xtensa/branch-cycle-contract.S',Path(__file__),*[source_path(root,n) for n in original]]},'limits':'Measured frontend redirection component; full window/exception/IRQ phase and fetch wait states remain open.'},indent=2)+'\n');print(f'PASS:{checks} branch-cycle contract checks/{len(controls)} defect controls',flush=True)
