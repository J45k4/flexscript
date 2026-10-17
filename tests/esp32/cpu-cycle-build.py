#!/usr/bin/env python3
"""Build GNU instruction-cycle probes and verify their actual guest-RAM records."""
import argparse,hashlib,json,re,subprocess
from pathlib import Path
from elf32_symbols import elf32_symbols
from cpu_cycle_protocol import layout,parse_ram,validate_timing
from cpu_controlflow_oracle import generate_control_blocks
p=argparse.ArgumentParser(description=__doc__)
for name in ('compiler','linker','ld','as','rom-ld','rom','work','report'):p.add_argument('--'+name,type=Path,required=True)
p.add_argument('--pattern-set',choices=('basic','followers','controlflow'),default='basic')
p.add_argument('--timing-profile',choices=('functional','lx6'),default='lx6')
a=p.parse_args();root=Path(__file__).resolve().parents[2];work=a.work.resolve();work.mkdir(parents=True,exist_ok=True);sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
inputs=set()
def imports(path):
 path=path.resolve()
 if path in inputs:return
 inputs.add(path)
 for name in re.findall(r'^import\s+"([^"]+)";',path.read_text(),re.M):imports(path.parent/name)
source=root/'tests/esp32/cpu-cycle-observe.flex';observer=root/'tests/xtensa/cpu-cycle-native.flex';assembly=root/('tests/xtensa/cycle-oracle/control.S' if a.pattern_set=='controlflow' else 'tests/xtensa/cycle-oracle/measure.S')
imports(source);imports(observer);inputs.update((assembly,Path(__file__),root/'tests/esp32/cpu_cycle_protocol.py',root/'tests/esp32/elf32_symbols.py',root/'tests/esp32/cpu_controlflow_oracle.py'))
before={str(path.relative_to(root)):sha(path) for path in inputs}
def run(cmd,timeout=40):
 q=subprocess.run([str(x) for x in cmd],cwd=root,capture_output=True,timeout=timeout)
 if q.returncode:
  (work/'command-failure.log').write_bytes(q.stdout+q.stderr)
  raise AssertionError((q.returncode,q.stdout[-1500:],q.stderr[-1500:]))
 return q
patterns=('nop','addi a7,a7,1','rsr a11,ccount','wsr a6,ps','wsr a6,sar','rsync','wsr a6,ps;rsync','wsr a6,sar;rsync','rsil a11,0','memw','s32i a7,a2,32','l32i a7,a2,32')
if a.pattern_set=='followers':
 patterns=('wsr a6,ps;nop','wsr a6,ps;nop;nop','wsr a6,ps;nop;nop;nop','wsr a6,ps;rsync;nop','wsr a6,sar;nop','wsr a6,sar;nop;rsync','wsr a6,sar;nop;nop;rsync','rsil a11,0;nop','rsil a11,0;rsync','rsil a11,0;nop;nop','wsr a6,ps;rsil a11,0','wsr a6,ps;rsr a11,ps')
blocks=['.global cc_pattern_set','.set cc_pattern_set,1'] if a.pattern_set=='followers' else []
table=[]
for kind,pattern in enumerate(patterns):
 for count in (0,1,2,4,8,16,32):
  for align in range(4):
   suffix=f'{kind}_{count}_{align}';begin='cc_begin_'+suffix;end='cc_end_'+suffix;block='cc_block_'+suffix
   blocks += [block+':',f' movi a10,{begin}',' s32i a10,a2,16',f' movi a10,{end}',' s32i a10,a2,20','.begin no-transform',f' j .Lcc_aligned_{suffix}','.balign 16',f'.Lcc_aligned_{suffix}:']
   if align&1:blocks.append(' nop.n')
   if align&2:blocks.append(' nop')
   blocks += ['.global '+begin,begin+':',' rsr a8,ccount',f'.rept {count}']
   blocks += [' '+op for op in pattern.split(';')]
   blocks += ['.endr','.global '+end,end+':',' rsr a9,ccount',' j cc_done','.end no-transform']
   table.append(' .word '+block)
blocks += ['.section .rodata.cc_table,"a"','.balign 4','cc_table:',*table]
if a.pattern_set=='controlflow':blocks=generate_control_blocks()
(work/'blocks.S').write_text('\n'.join(blocks)+'\n')
obj=work/'measure.o';run([getattr(a,'as'),'--text-section-literals','-I',work,assembly,'-o',obj]);runner=work/'native-observer';run([a.compiler,observer,'-o',runner]);manifest=[]
for clock in (40,160):
 label=f'clock{clock}';folder=work/label;folder.mkdir(exist_ok=True)
 wrapper=folder/'probe.flex';wrapper.write_text('import '+json.dumps(str(source))+';\nfn co_clock(){return '+str(clock)+';}\n')
 unlinked=folder/'unlinked.elf';elf=folder/'probe.elf'
 run([a.compiler,'--target','esp32-radio-elf',wrapper,'-o',unlinked]);run([a.linker,'--firmware',unlinked,'--output',elf,'--object',obj,'--ld',a.ld,'--rom',a.rom_ld])
 image=elf.read_bytes();layout(image);ready=elf32_symbols(image)['cc_ready_snapshot'];records=folder/'native.records'
 q=run([runner,elf,a.rom,ready,records,1 if a.timing_profile=='lx6' else 0],timeout=240);(folder/'native.stdout').write_bytes(q.stdout);(folder/'native.stderr').write_bytes(q.stderr)
 parsed=validate_timing(parse_ram(records.read_bytes(),image),image,a.timing_profile)
 header=Path(str(records)+'.header.uart');data=header.read_bytes();match=re.fullmatch(rb'CCOST START CLOCK ([0-9a-f]{16}) SOURCE ([0-9a-f]{16}) PERIOD ([0-9a-f]{16}) DIV ([0-9a-f]{16}) ROMTICKS ([0-9a-f]{16})\r\n',data);assert match
 assert tuple(int(v,16) for v in match.groups())==((40,0,0,0,13) if clock==40 else (160,1,1,0,160))
 manifest.append({'clock_mhz':clock,'elf':str(elf.relative_to(work)),'sha256':sha(elf),'native_records':str(records.relative_to(work)),'native_records_sha256':sha(records),'native_header':str(header.relative_to(work)),'native_header_sha256':sha(header),'records':len(parsed),'snapshot_PC':ready})
 if a.pattern_set!='basic':manifest[-1]['pattern_set']=a.pattern_set
 print('PASS',a.pattern_set,clock,'672 native RAM records;GNUbytes/PS/registers/counters validated',flush=True)
assert before=={str(path.relative_to(root)):sha(path) for path in inputs}
(work/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
report={'pass':True,'pattern_set':a.pattern_set,'physical_hardware':False,'images':manifest,'native_transport':'actual guest RAM snapshot at GNU cc_ready_snapshot before UART dumping;header UART is actual emitted output','native_records':1344,'GNU_instruction_patterns':12,'counts':[0,1,2,4,8,16,32],'alignments':4,'PS_INTLEVELs':[0,15],'timing_profile':a.timing_profile,'one_cycle_per_instruction_baseline_verified':a.timing_profile=='functional','measured_LX6_timing_verified':a.timing_profile=='lx6','source_sha256':before,'compiler_sha256':sha(a.compiler),'linker_sha256':sha(a.linker),'GNU_assembler_sha256':sha(getattr(a,'as')),'GNU_ld_sha256':sha(a.ld),'ROM_ld_sha256':sha(a.rom_ld),'ROM_sha256':sha(a.rom),'native_observer_sha256':sha(runner)}
a.report.write_text(json.dumps(report,indent=2)+'\n')
