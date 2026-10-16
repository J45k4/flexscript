#!/usr/bin/env python3
"""Replay exact timer-priority firmware against artifact-bound silicon captures."""
import argparse,hashlib,json,subprocess,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'esp32'))
from timer_irq_protocol import parse,parse_ram,audit,header
p=argparse.ArgumentParser(description=__doc__)
for name in ('runner','checkpoint','rom','work','report'):p.add_argument('--'+name,type=Path,required=True)
a=p.parse_args();base=a.checkpoint.resolve();work=a.work.resolve();work.mkdir(parents=True,exist_ok=True);sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
proof=json.loads((base/'measurement-report.json').read_text());assert proof['measurements_verified'] and proof['physical_records']==40 and proof['all2_full4MiB_unchanged_and_reset']
assert sha(base/'artifact-sha256.json')==proof['artifact_index_sha256'];index=json.loads((base/'artifact-sha256.json').read_text())
def bound(p):assert sha(p)==index[str(p.relative_to(base))],p
bound(base/'matrix/manifest.json');manifest=json.loads((base/'matrix/manifest.json').read_text());runner_hash=sha(a.runner);results=[]
assert sha(a.rom)=='9115bbcd03da9f54d3baca5ad94d588a43da54ed332347137ba3dc9010df258b'
for item in manifest:
 clock=item['clock_mhz'];elf=base/'matrix'/item['elf'];bound(elf);assert sha(elf)==item['sha256'];image=elf.read_bytes();pj=base/f'physical-clock{clock}/physical.json';uart=base/f'physical-clock{clock}/uart.bin';bound(pj);bound(uart);hproof=json.loads(pj.read_text());assert hproof['pass'] and hproof['before_matches'] and hproof['after_matches'] and hproof['final_reset'] and not hproof['flash_write_requested'];physical=audit(parse(uart.read_bytes(),image,clock),image);assert physical==hproof['observations'] and sha(uart)==hproof['UART_sha256']
 dest=work/f'clock{clock}';dest.mkdir(exist_ok=True);raw=dest/'native.records';q=subprocess.run(list(map(str,[a.runner.resolve(),elf,a.rom.resolve(),item['snapshot_PC'],raw,1])),capture_output=True,timeout=300);(dest/'stdout').write_bytes(q.stdout);(dest/'stderr').write_bytes(q.stderr);assert q.returncode==0,(q.stdout,q.stderr);native=audit(parse_ram(raw.read_bytes(),image),image);head=Path(str(raw)+'.header.uart');header(head.read_bytes(),clock)
 differences=[];overlaps=0;handler_events=0;gated_entries=0;waiti_events=0
 for h,n in zip(physical,native):
  case=h['CASE'];changed={k:[h[k],n[k]] for k in h if h[k]!=n[k] and k not in ('CC0','CCEND') and not k.endswith(('_CC','_RETCC'))}
  allowed={'CAUSE'} if case==0 and h['REPEAT']==0 else set()
  if 3<=case<6:allowed.add('E0_COMPARE')
  assert set(changed)<=allowed,(clock,case,changed)
  if 'CAUSE' in changed:assert changed['CAUSE']==[4,0]
  if 3<=case<6:
   waiti_events+=1;assert (h['E0_CC']-h['E0_COMPARE'])&0xffffffff==9
   assert (n['E0_CC']-n['E0_COMPARE'])&0xffffffff==9
   assert ((h['E0_COMPARE']-h['CC0'])&0xffffffff)-((n['E0_COMPARE']-n['CC0'])&0xffffffff)==-2
  else:
   assert (h['E0_CC']-h['CC0'])&0xffffffff==(n['E0_CC']-n['CC0'])&0xffffffff==10;gated_entries+=1
  handler_events+=h['COUNT']
  for i in range(h['COUNT']):
   if case==7 and i==1:assert (h[f'E{i}_CC']-h[f'E{i}_COMPARE'])&0xffffffff==(n[f'E{i}_CC']-n[f'E{i}_COMPARE'])&0xffffffff==8
   if (case==6 and i>0) or (case==9 and i==2):
    assert (h[f'E{i}_CC']-h[f'E{i-1}_RETCC'])&0xffffffff==(n[f'E{i}_CC']-n[f'E{i-1}_RETCC'])&0xffffffff==14;overlaps+=1
  differences.append({'case':case,'repeat':h['REPEAT'],'all_raw_differences':{k:[h[k],n[k]] for k in h if h[k]!=n[k]}})
 (dest/'raw-differences.json').write_text(json.dumps(differences,indent=2)+'\n');assert sha(a.runner)==runner_hash
 results.append({'clock_MHz':clock,'cases':20,'handler_events':handler_events,'PC_PS_EPS_pending_ACK_marker_fields_matching':True,'pending_gate_intervals_matching':gated_entries,'RFI_pending_overlaps_matching':overlaps,'WAITI_target_phase_intervals_matching':waiti_events,'initial_EXCCAUSE_difference_retained':[4,0],'ELF_sha256':sha(elf),'physical_UART_sha256':sha(uart),'native_RAM_sha256':sha(raw),'actual_header_UART_sha256':sha(head)})
 print('PASS timer IRQ',clock,'20 cases:priority/context/order match;entry/return overlap verified;boot/expiry/body differences retained',flush=True)
a.report.write_text(json.dumps({'pass':True,'scope_complete':False,'physical_hardware_accessed':False,'cases':results,'records':40,'handler_events':sum(x['handler_events'] for x in results),'runner_sha256':runner_hash,'remaining_related_issues':['T376','T379'],'limits':'No global timing/context normalization. ISR body and initial boot CAUSE remain explicit;NMI/debug/CPU1/general pipeline remain open.'},indent=2)+'\n')
