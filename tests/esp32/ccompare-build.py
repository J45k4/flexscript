#!/usr/bin/env python3
"""Build independent CPU comparator firmware and validate actual native RAM."""
import argparse,hashlib,json,re,subprocess
from pathlib import Path
from elf32_symbols import elf32_symbols
from ccompare_protocol import generate_blocks,layout,parse_ram,header,ROWS
p=argparse.ArgumentParser(description=__doc__)
for name in ('compiler','linker','ld','as','rom-ld','rom','work','report'):p.add_argument('--'+name,type=Path,required=True)
a=p.parse_args();root=Path(__file__).resolve().parents[2];work=a.work.resolve();work.mkdir(parents=True,exist_ok=True);sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
inputs=set()
def imports(path):
 path=path.resolve()
 if path in inputs:return
 inputs.add(path)
 for name in re.findall(r'^import\s+"([^"]+)";',path.read_text(),re.M):imports(path.parent/name)
source=root/'tests/esp32/ccompare-observe.flex';observer=root/'tests/xtensa/ccompare-native.flex';assembly=root/'tests/xtensa/cycle-oracle/ccompare.S'
imports(source);imports(observer);inputs.update((assembly,Path(__file__),root/'tests/esp32/ccompare_protocol.py',root/'tests/esp32/elf32_symbols.py'));before={str(p.relative_to(root)):sha(p) for p in inputs}
def run(cmd,timeout=60):
 q=subprocess.run([str(x) for x in cmd],cwd=root,capture_output=True,timeout=timeout)
 if q.returncode:
  (work/'command-failure.log').write_bytes(q.stdout+q.stderr)
  raise AssertionError((q.returncode,q.stdout[-1600:],q.stderr[-2200:]))
 return q
(work/'blocks.S').write_text('\n'.join(generate_blocks())+'\n');obj=work/'measure.o';run([getattr(a,'as'),'--text-section-literals','-I',work,assembly,'-o',obj]);runner=work/'native-observer';run([a.compiler,observer,'-o',runner]);manifest=[]
for clock in (40,160):
 folder=work/f'clock{clock}';folder.mkdir(exist_ok=True);wrapper=folder/'probe.flex';wrapper.write_text('import '+json.dumps(str(source))+';\nfn ct_clock(){return '+str(clock)+';}\n');unlinked=folder/'unlinked.elf';elf=folder/'probe.elf'
 run([a.compiler,'--target','esp32-radio-elf',wrapper,'-o',unlinked]);run([a.linker,'--firmware',unlinked,'--output',elf,'--object',obj,'--ld',a.ld,'--rom',a.rom_ld]);image=elf.read_bytes();layout(image);ready=elf32_symbols(image)['ct_ready_snapshot'];records=folder/'native.records'
 q=run([runner,elf,a.rom,ready,records,1],timeout=240);(folder/'native.stdout').write_bytes(q.stdout);(folder/'native.stderr').write_bytes(q.stderr);rows=parse_ram(records.read_bytes(),image);uart=Path(str(records)+'.header.uart');header(uart.read_bytes(),clock)
 manifest.append({'clock_mhz':clock,'elf':str(elf.relative_to(work)),'sha256':sha(elf),'native_records':str(records.relative_to(work)),'native_records_sha256':sha(records),'native_header':str(uart.relative_to(work)),'native_header_sha256':sha(uart),'records':len(rows),'snapshot_PC':ready,'record_words':16})
 print('PASS CCOMPARE',clock,len(rows),'actual native comparator records;GNU CSR layout checked',flush=True)
assert before=={str(p.relative_to(root)):sha(p) for p in inputs}
(work/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n');a.report.write_text(json.dumps({'pass':True,'physical_hardware':False,'family':'CCOMPARE-masked-v1','record_words':16,'images':manifest,'native_records':ROWS*2,'timing_profile':'current-partial-LX6','comparator_semantics_calibrated':False,'native_transport':'actual guest-RAM GNU checkpoint before measurement UART output;actual header separately captured','source_sha256':before,'compiler_sha256':sha(a.compiler),'linker_sha256':sha(a.linker),'GNU_assembler_sha256':sha(getattr(a,'as')),'GNU_ld_sha256':sha(a.ld),'ROM_ld_sha256':sha(a.rom_ld),'ROM_sha256':sha(a.rom),'native_observer_sha256':sha(runner)},indent=2)+'\n')
