#!/usr/bin/env python3
"""Compare actual native guest-RAM timing with both retained silicon UART matrices."""
import argparse,hashlib,json,re,subprocess
from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'esp32'))
from cpu_cycle_protocol import parse,parse_ram,pattern_set,validate_timing
p=argparse.ArgumentParser(description=__doc__)
for name in ('runner','basic','followers','rom','work','report'):p.add_argument('--'+name,type=Path,required=True)
p.add_argument('--controlflow',type=Path)
a=p.parse_args();work=a.work.resolve();work.mkdir(parents=True,exist_ok=True)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
assert sha(a.rom)=='9115bbcd03da9f54d3baca5ad94d588a43da54ed332347137ba3dc9010df258b'
runner_hash=sha(a.runner);results=[]
references=[a.basic.resolve(),a.followers.resolve()]
if a.controlflow:references.append(a.controlflow.resolve())
for family,ref in enumerate(references):
 proof=json.loads((ref/'measurement-report.json').read_text());assert proof['measurements_verified'] and proof['physical_records']==1344
 assert sha(ref/'artifact-sha256.json')==proof['artifact_index_sha256']
 hashes=json.loads((ref/'artifact-sha256.json').read_text())
 def bound(path):assert sha(path)==hashes[str(path.relative_to(ref))],path
 for path in (ref/'matrix/manifest.json',ref/'native.json'):bound(path)
 manifest=json.loads((ref/'matrix/manifest.json').read_text());build=json.loads((ref/'native.json').read_text());assert build['pass'] and build['images']==manifest
 for item in manifest:
  clock=item['clock_mhz'];elf=ref/'matrix'/item['elf'];bound(elf);image=elf.read_bytes();assert sha(elf)==item['sha256'] and pattern_set(image)==family
  folder=ref/f'physical-clock{clock}';physical_report=folder/'physical.json';uart=folder/'uart.bin';bound(physical_report);bound(uart)
  physical_proof=json.loads(physical_report.read_text());assert physical_proof['pass'] and physical_proof['before_matches'] and physical_proof['after_matches'] and physical_proof['final_reset'] and not physical_proof['flash_write_requested']
  assert sha(uart)==physical_proof['UART_sha256'] and sha(elf)==physical_proof['ELF_sha256']
  physical=parse(uart.read_bytes(),image,clock);assert physical==physical_proof['observations']
  label=('basic','followers','controlflow')[family]+f'-clock{clock}';dest=work/label;dest.mkdir(exist_ok=True);records=dest/'native.records'
  q=subprocess.run([str(x) for x in (a.runner.resolve(),elf,a.rom.resolve(),item['snapshot_PC'],records,1)],capture_output=True,timeout=240)
  (dest/'stdout').write_bytes(q.stdout);(dest/'stderr').write_bytes(q.stderr);assert q.returncode==0,(label,q.returncode,q.stdout[-1000:],q.stderr[-1000:])
  native=validate_timing(parse_ram(records.read_bytes(),image),image,'lx6')
  header=Path(str(records)+'.header.uart');match=re.fullmatch(rb'CCOST START CLOCK ([0-9a-f]{16}) SOURCE ([0-9a-f]{16}) PERIOD ([0-9a-f]{16}) DIV ([0-9a-f]{16}) ROMTICKS ([0-9a-f]{16})\r\n',header.read_bytes());assert match
  assert tuple(int(v,16) for v in match.groups())==((40,0,0,0,13) if clock==40 else (160,1,1,0,160))
  for n,h in zip(native,physical):assert all(n[k]==h[k] for k in n if k not in ('START','END')),(label,n,h)
  assert sha(a.runner)==runner_hash
  results.append({'family':family,'clock_MHz':clock,'matched_intervals':672,'all_non_counter_architectural_fields_match':True,'ELF_sha256':sha(elf),'native_RAM_sha256':sha(records),'physical_UART_sha256':sha(uart),'actual_native_header_UART_sha256':sha(header),'reference_report_sha256':sha(ref/'measurement-report.json')})
  print('PASS',label,'672 silicon/native intervals and all architectural fields match',flush=True)
a.report.write_text(json.dumps({'pass':True,'scope_complete':False,'physical_hardware_accessed':False,'runner_sha256':runner_hash,'records':len(results)*672,'cases':results,'limits':'Straight-line measured IRAM/SRAM instruction families with INTENABLE0. Counter origins differ. Native data is actual guest RAM; full measurement UART is physical only. Full CPI, IRQ phase and broader cache frontend remain open.'},indent=2)+'\n')
print(f'PASS:{len(results)*672} actual silicon/native timing intervals',flush=True)
