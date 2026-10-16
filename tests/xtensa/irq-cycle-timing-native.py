#!/usr/bin/env python3
"""Replay unchanged IRQ NOP/marker firmware against artifact-bound silicon data."""
import argparse,hashlib,json,subprocess,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'esp32'))
from irq_cycle_protocol import parse,parse_ram,record_words,header
p=argparse.ArgumentParser(description=__doc__)
for name in ('runner','nop','marker','rom','work','report'):p.add_argument('--'+name,type=Path,required=True)
p.add_argument("--pending-status",choices=("comparators","legacy"),default="comparators")
a=p.parse_args();work=a.work.resolve();work.mkdir(parents=True,exist_ok=True);sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest();results=[]
assert sha(a.rom)=='9115bbcd03da9f54d3baca5ad94d588a43da54ed332347137ba3dc9010df258b';runner_hash=sha(a.runner)
for family,base in [('nop',a.nop.resolve()),('marker',a.marker.resolve())]:
 report=json.loads((base/'measurement-report.json').read_text());assert report['measurements_verified'] and report['physical_records']==768 and sha(base/'artifact-sha256.json')==report['artifact_index_sha256']
 hashes=json.loads((base/'artifact-sha256.json').read_text())
 def bound(path):assert sha(path)==hashes[str(path.relative_to(base))],path
 bound(base/'matrix/manifest.json');manifest=json.loads((base/'matrix/manifest.json').read_text())
 for item in manifest:
  clock=item['clock_mhz'];elf=base/'matrix'/item['elf'];bound(elf);image=elf.read_bytes();assert sha(elf)==item['sha256']
  physical_json=base/f'physical-clock{clock}/physical.json';uart=base/f'physical-clock{clock}/uart.bin';bound(physical_json);bound(uart);proof=json.loads(physical_json.read_text());assert proof['pass'] and proof['before_matches'] and proof['after_matches'] and proof['final_reset'] and not proof['flash_write_requested']
  assert sha(uart)==proof['UART_sha256'] and sha(elf)==proof['ELF_sha256'];physical=parse(uart.read_bytes(),image,clock);assert physical==proof['observations']
  dest=work/f'{family}-clock{clock}';dest.mkdir(exist_ok=True);raw=dest/'native.records';cmd=[a.runner.resolve(),elf,a.rom.resolve(),item['snapshot_PC'],raw,1,len(record_words(image))];q=subprocess.run([str(x) for x in cmd],capture_output=True,timeout=240);(dest/'stdout').write_bytes(q.stdout);(dest/'stderr').write_bytes(q.stderr);assert q.returncode==0,(family,clock,q.returncode,q.stdout[-1000:],q.stderr[-1800:])
  native=parse_ram(raw.read_bytes(),image);head=Path(str(raw)+'.header.uart');header(head.read_bytes(),clock);differences=[]
  for h,n in zip(physical,native):
   assert ((h['IRQCC']-h['START'])&0xffffffff)==((n['IRQCC']-n['START'])&0xffffffff),('entry',family,clock,h,n)
   assert ((h['END']-h['RETCC'])&0xffffffff)==((n['END']-n['RETCC'])&0xffffffff),('return',family,clock,h,n)
   changed={k:[h[k],n[k]] for k in h if k not in ('START','IRQCC','RETCC','END') and h[k]!=n[k]}
   # Preserve the still-open CPU-comparator status mismatch explicitly.
   if a.pending_status=='legacy':
    assert set(changed)=={'PENDING','AFTERPENDING'},(family,clock,changed)
    assert changed['PENDING']==[0x180c0,128] and changed['AFTERPENDING']==[0x18040,0]
   else:assert not changed,(family,clock,changed)
   differences.append({'identity':[h[k] for k in ('PROFILE','GATE','TALIGN','RALIGN','REPEAT')],'raw_architectural_differences':changed})
  (dest/'pending-status-differences.json').write_text(json.dumps(differences,indent=2)+'\n')
  assert sha(a.runner)==runner_hash
  results.append({'family':family,'clock_MHz':clock,'records':384,'entry_intervals_match':384,'return_intervals_match':384,'EPC_and_marker_fields_match':True,'raw_pending_status_mismatches_retained':384 if a.pending_status=='legacy' else 0,'ELF_sha256':sha(elf),'physical_UART_sha256':sha(uart),'native_RAM_sha256':sha(raw),'actual_native_header_UART_sha256':sha(head)})
  print('PASS',family,clock,'384 entry/return intervals,EPCs and marker effects match;raw CPU timer status verified in selected mode',flush=True)
a.report.write_text(json.dumps({'pass':True,'scope_complete':False,'physical_hardware_accessed':False,'runner_sha256':runner_hash,'records':1536,'entry_return_intervals_matching_silicon':3072,'cases':results,'pending_status_mode':a.pending_status,'raw_pending_status_issue':'T361' if a.pending_status=='legacy' else None,'limits':'Level1 IRQ7 temporary vectors and forced RFE target;counter origins differ,comparator ISR delivery and suffix timing remain separate.Full measurement UART is physical only.'},indent=2)+'\n');print('PASS:1536 IRQ cases/3072 entry-return intervals;raw timer status verified',flush=True)
