#!/usr/bin/env python3
"""Replay the exact pending-source silicon probes with raw differences retained."""
import argparse,hashlib,json,subprocess,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'esp32'))
from pending_wake_protocol import parse,parse_ram,header,IDS
p=argparse.ArgumentParser(description=__doc__)
for name in ('runner','checkpoint','rom','work','report'):p.add_argument('--'+name,type=Path,required=True)
a=p.parse_args();base=a.checkpoint.resolve();work=a.work.resolve();work.mkdir(parents=True,exist_ok=True);sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest();proof=json.loads((base/'measurement-report.json').read_text());assert proof['checkpoint_verified'] and proof['physical_records']==128 and proof['all2_full4MiB_unchanged_and_reset'];assert sha(base/'artifact-sha256.json')==proof['artifact_index_sha256'];index=json.loads((base/'artifact-sha256.json').read_text());runner_hash=sha(a.runner);assert sha(a.rom)=='9115bbcd03da9f54d3baca5ad94d588a43da54ed332347137ba3dc9010df258b'
def bound(path):assert sha(path)==index[str(path.relative_to(base))],path
results=[]
for clock in (40,160):
 matrix=base/('matrix' if clock==40 else 'matrix-v2');bound(matrix/'manifest.json');item=next(x for x in json.loads((matrix/'manifest.json').read_text()) if x['clock_mhz']==clock);elf=matrix/item['elf'];bound(elf);assert sha(elf)==item['sha256'];image=elf.read_bytes();folder=base/f'physical-clock{clock}';bound(folder/'physical.json');bound(folder/'uart.bin');guard=json.loads((folder/'physical.json').read_text());assert guard['before_matches'] and guard['after_matches'] and guard['final_reset'] and not guard['flash_write_requested'];assert sha(folder/'uart.bin')==guard['UART_sha256'];assert next(x for x in proof['cases'] if x['clock_MHz']==clock)['capture_reaudit_pass'];hardware=parse((folder/'uart.bin').read_bytes(),image,clock)
 dest=work/f'clock{clock}';dest.mkdir(exist_ok=True);raw=dest/'native.records';q=subprocess.run(list(map(str,[a.runner.resolve(),elf,a.rom.resolve(),item['snapshot_PC'],raw,1])),capture_output=True,timeout=350);(dest/'stdout').write_bytes(q.stdout);(dest/'stderr').write_bytes(q.stderr);assert q.returncode==0,(q.stdout,q.stderr);native=parse_ram(raw.read_bytes(),image);head=Path(str(raw)+'.header.uart');header(head.read_bytes(),clock);diffs=[]
 for h,n in zip(hardware,native):
  interval=12 if h['GATE']==0 else 9
  assert ((h['IRQCC']-h['T0'])&0xffffffff)==((n['IRQCC']-n['T0'])&0xffffffff)==interval
  assert h['MARKER']==n['MARKER']==0 and h['EPC']==h['STREAMPC'] and n['EPC']==n['STREAMPC']
  changed={k:[h[k],n[k]] for k in h if h[k]!=n[k]};assert not(set(changed)-{'IRQCC','RETCC','T0','T1','PREPENDING','CAUSE0'})
  if 'CAUSE0' in changed:assert h['SELECTOR']==0 and h['REPEAT']==0 and changed['CAUSE0']==[4,0]
  diffs.append({'identity':[h[k] for k in IDS],'entry_interval_cycles':interval,'all_raw_differences':changed,'physical_handler_interval':(h['RETCC']-h['IRQCC'])&0xffffffff,'native_handler_interval':(n['RETCC']-n['IRQCC'])&0xffffffff})
 (dest/'raw-differences.json').write_text(json.dumps(diffs,indent=2)+'\n');assert sha(a.runner)==runner_hash
 results.append({'clock_MHz':clock,'records':64,'WAITI_entry_intervals_matching_12cycles':32,'PS_unmask_entry_intervals_matching_9cycles':32,'ELF_sha256':sha(elf),'physical_UART_sha256':sha(folder/'uart.bin'),'native_RAM_sha256':sha(raw),'actual_header_UART_sha256':sha(head),'GPIO_MMIO_counter_and_early_visibility_gaps_retained':True})
 print('PASS pending wake',clock,'64 exact entry intervals andinterrupted architecture states;GPIO/boot raw differences retained',flush=True)
a.report.write_text(json.dumps({'pass':True,'scope_complete':False,'physical_hardware_accessed':False,'records':128,'WAITI_entry_intervals_matching_12cycles':64,'PS_unmask_entry_intervals_matching_9cycles':64,'cases':results,'runner_sha256':runner_hash,'counter_or_context_differences_normalized':False,'remaining_issues':['T389 early GPIO source','T391 GPIO MMIO timing','T376 initial CAUSE','T387 external routing','T385 future mixed-source wake']},indent=2)+'\n')
