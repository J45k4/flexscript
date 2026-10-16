#!/usr/bin/env python3
"""Replay exact masked-comparator firmware against artifact-bound silicon data."""
import argparse,hashlib,json,subprocess,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'esp32'))
from ccompare_protocol import parse,parse_ram,header
p=argparse.ArgumentParser(description=__doc__)
for name in ('runner','checkpoint','rom','work','report'):p.add_argument('--'+name,type=Path,required=True)
a=p.parse_args();base=a.checkpoint.resolve();work=a.work.resolve();work.mkdir(parents=True,exist_ok=True)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
assert sha(a.rom)=='9115bbcd03da9f54d3baca5ad94d588a43da54ed332347137ba3dc9010df258b'
proof=json.loads((base/'measurement-report.json').read_text());assert proof['measurements_verified'] and proof['physical_records']==48 and proof['all2_full4MiB_unchanged_and_reset']
assert sha(base/'artifact-sha256.json')==proof['artifact_index_sha256'];index=json.loads((base/'artifact-sha256.json').read_text())
def bound(path):assert sha(path)==index[str(path.relative_to(base))],path
bound(base/'matrix/manifest.json');manifest=json.loads((base/'matrix/manifest.json').read_text());results=[];runner_hash=sha(a.runner)
for item in manifest:
 clock=item['clock_mhz'];elf=base/'matrix'/item['elf'];bound(elf);assert sha(elf)==item['sha256'];image=elf.read_bytes()
 physical_json=base/f'physical-clock{clock}/physical.json';uart=base/f'physical-clock{clock}/uart.bin';bound(physical_json);bound(uart);hproof=json.loads(physical_json.read_text());assert hproof['pass'] and hproof['before_matches'] and hproof['after_matches'] and hproof['final_reset'] and not hproof['flash_write_requested']
 assert sha(uart)==hproof['UART_sha256'] and sha(elf)==hproof['ELF_sha256'];physical=parse(uart.read_bytes(),image,clock);assert physical==hproof['observations']
 dest=work/f'clock{clock}';dest.mkdir(exist_ok=True);raw=dest/'native.records';q=subprocess.run(list(map(str,[a.runner.resolve(),elf,a.rom.resolve(),item['snapshot_PC'],raw,1])),capture_output=True,timeout=250);(dest/'stdout').write_bytes(q.stdout);(dest/'stderr').write_bytes(q.stderr);assert q.returncode==0,(q.stdout,q.stderr)
 native=parse_ram(raw.read_bytes(),image);head=Path(str(raw)+'.header.uart');header(head.read_bytes(),clock);differences=[]
 for h,n in zip(physical,native):
  for key in ('TIMER','MODE','REPEAT','C0','C1','C2','P0','PCLEAN','PPRE','PPOST','PINTCLR','PREWRITE','PALLCLR'):assert h[key]==n[key],(key,clock,h,n)
  prefix_gap=((h['TARGET']-h['CCPRE'])&0xffffffff)-((n['TARGET']-n['CCPRE'])&0xffffffff)
  assert prefix_gap==(-2 if h['MODE']==0 else 0),(clock,h,n)
  assert h['TARGET']==h['READBACK'] and n['TARGET']==n['READBACK']
  if h['MODE']<2:assert ((h['CCPOST']-h['CCPRE'])&0xffffffff)==((n['CCPOST']-n['CCPRE'])&0xffffffff)==84
  else:assert h['CCPRE']==n['CCPRE'] and h['CCPOST']==n['CCPOST']
  assert ((h['CCEND']-h['CCPOST'])&0xffffffff)-((n['CCEND']-n['CCPOST'])&0xffffffff)==3
  differences.append({'identity':[h[k] for k in ('TIMER','MODE','REPEAT')],'raw_differences':{k:[h[k],n[k]] for k in h if h[k]!=n[k]}})
 (dest/'raw-differences.json').write_text(json.dumps(differences,indent=2)+'\n');assert sha(a.runner)==runner_hash
 results.append({'clock_MHz':clock,'records':24,'raw_pending_and_CCOMPARE_samples_all_match':True,'pending_samples_matching':168,'CCOMPARE_samples_matching':72,'suffix_counter_gap_retained_cycles':3,'normal_program_readback_prefix_gap_retained_cycles':2,'ELF_sha256':sha(elf),'physical_UART_sha256':sha(uart),'native_RAM_sha256':sha(raw),'actual_header_UART_sha256':sha(head)})
 print('PASS comparator',clock,'24 cases:all raw pending/compare samples match;prefix/suffix timing differences retained',flush=True)
a.report.write_text(json.dumps({'pass':True,'scope_complete':False,'physical_hardware_accessed':False,'records':48,'cases':results,'runner_sha256':runner_hash,'pending_samples_matching':336,'CCOMPARE_samples_matching':144,'remaining_timing_issues':['T369','T374'],'limits':'Masked original ESP32 comparators only;ISR priority/WAITI scheduling remain T371.Counter origins and prefix/suffix timing remain explicit.'},indent=2)+'\n')
