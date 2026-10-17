#!/usr/bin/env python3
"""Audit raw pending-source captures without normalizing any counter origins."""
import argparse,collections,hashlib,json
from pathlib import Path
from pending_wake_protocol import parse,parse_ram,validate,IDS,WORDS
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--checkpoint',type=Path,required=True);p.add_argument('--report',type=Path,required=True);a=p.parse_args();base=a.checkpoint.resolve();sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def audit(rows,image):
 validate(rows,image)
 for row in rows:
  level=row['LEVEL'];assert row['MARKER']==0 and row['EPC']==row['STREAMPC']
  assert row['IRQPS']==row['PS']|16|(level if level>1 else 0) and row['EPS']==row['PS']
  assert ((row['IRQCC']-row['T0'])&0xffffffff)==(12 if row['GATE']==0 else 9)
 return rows
results=[];controls=[]
for clock in (40,160):
 matrix=base/('matrix' if clock==40 else 'matrix-v2');manifest=json.loads((matrix/'manifest.json').read_text());item=next(x for x in manifest if x['clock_mhz']==clock);elf=matrix/item['elf'];image=elf.read_bytes();assert sha(elf)==item['sha256']
 folder=base/f'physical-clock{clock}';guard=json.loads((folder/'physical.json').read_text());uart=folder/'uart.bin';assert guard['ram_only'] and not guard['flash_write_requested'] and guard['before_matches'] and guard['after_matches'] and guard['final_reset'];assert sha(elf)==guard['ELF_sha256'] and sha(uart)==guard['UART_sha256']
 hardware=audit(parse(uart.read_bytes(),image,clock),image);native_path=matrix/item['native_records'];assert sha(native_path)==item['native_records_sha256'];native=parse_ram(native_path.read_bytes(),image);differences=[]
 for h,n in zip(hardware,native):
  # Non-counter state agrees except the separately tracked early GPIO and boot cause.
  changed={k:[h[k],n[k]] for k in h if h[k]!=n[k]};assert not(set(changed)-{'IRQCC','RETCC','T0','T1','PREPENDING','CAUSE0'})
  assert ((n['IRQCC']-n['T0'])&0xffffffff)==9
  if 'CAUSE0' in changed:assert h['SELECTOR']==0 and h['REPEAT']==0 and changed['CAUSE0']==[4,0]
  differences.append({'identity':[h[k] for k in IDS],'all_raw_differences':changed,'physical_entry_interval':(h['IRQCC']-h['T0'])&0xffffffff,'native_entry_interval':(n['IRQCC']-n['T0'])&0xffffffff,'physical_handler_interval':(h['RETCC']-h['IRQCC'])&0xffffffff,'native_handler_interval':(n['RETCC']-n['IRQCC'])&0xffffffff})
 (folder/'raw-differences-audited.json').write_text(json.dumps(differences,indent=2)+'\n')
 entry=collections.Counter((r['GATE'],(r['IRQCC']-r['T0'])&0xffffffff) for r in hardware);assert entry=={(0,12):32,(1,9):32}
 results.append({'clock_MHz':clock,'records':64,'WAITI_entry_intervals_12cycles':32,'PS_unmask_entry_intervals_9cycles':32,'original_guard_report_pass':guard['pass'],'original_report_retained':str((folder/'physical.json').relative_to(base)),'capture_reaudit_pass':True,'ELF_sha256':sha(elf),'UART_sha256':sha(uart),'native_RAM_sha256':sha(native_path),'early_GPIO_pending_differences':sum('PREPENDING' in d['all_raw_differences'] for d in differences),'all_raw_differences_retained':str((folder/'raw-differences-audited.json').relative_to(base))})
 if clock==40:
  for name,field,value in [('entry-one-cycle-early','IRQCC',hardware[0]['IRQCC']-1),('wrong-level','LEVEL',3),('wrong-EPS','EPS',hardware[0]['EPS']^1),('wrong-EPC','EPC',hardware[0]['EPC']+3),('wrong-pending','IRQPENDING',0),('wrong-marker','MARKER',1)]:
   rows=[dict(r) for r in hardware];rows[0][field]=value
   try:audit(rows,image)
   except AssertionError:controls.append({'control':name,'rejected':True})
   else:raise AssertionError(name)
  data=uart.read_bytes()
  bads=[('missing-complete',data.replace(b'PENDING COMPLETE',b'OTHER COMPLETE')),('wrong-identity',data.replace(b'PENDING SOURCE 0000000000000000',b'PENDING SOURCE 0000000000000001',1)),('out-of-range',data.replace(b'SELECTOR 0000000000000000',b'SELECTOR 0000000100000000',1)),('missing-row',b'\r\n'.join(line for line in data.split(b'\r\n') if not line.startswith(b'PENDING SOURCE 0000000000000000 GATE 0000000000000000 ALIGN 0000000000000000 REPEAT 0000000000000001 ')))]
  for name,bad in bads:
   try:parse(bad,image,clock)
   except (AssertionError,ValueError):controls.append({'control':name,'rejected':True})
   else:raise AssertionError(name)
assert len(controls)==10
report={'pass':True,'measurements_verified':True,'scope_complete':False,'physical_records':128,'physical_WAITI_entry_intervals_matching_12cycles':64,'physical_PS_unmask_entry_intervals_matching_9cycles':64,'native_WAITI_entry_intervals_still_9cycles':64,'native_PS_unmask_entry_intervals_matching_9cycles':64,'all2_full4MiB_unchanged_and_reset':True,'physical_flash_written':False,'production_model_changed':False,'counter_or_context_differences_normalized':False,'cases':results,'negative_controls':controls,'remaining_issues':['T390 pending WAITI3-cycle phase','T389 early GPIO CPU visibility','T391 GPIO MMIO/fence timing','T387 external routes beyond CPU1','T376 initial CAUSE','T385 future mixed-source suspension','T371 full timer delivery','T223 full emulator']}
a.report.write_text(json.dumps(report,indent=2)+'\n');print('PASS128 captured records;WAITI12 versus PS9 cycles;all raw differences and initial guard failure retained;10 forged captures rejected',flush=True)
