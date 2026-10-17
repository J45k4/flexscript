#!/usr/bin/env python3
"""Replay literal-counter expiry firmware against artifact-bound silicon data."""
import argparse,hashlib,json,subprocess,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'esp32'))
from timer_expiry_protocol import parse,parse_ram,audit,header,WORDS
p=argparse.ArgumentParser(description=__doc__)
for name in ('runner','checkpoint','rom','work','report'):p.add_argument('--'+name,type=Path,required=True)
a=p.parse_args();base=a.checkpoint.resolve();work=a.work.resolve();work.mkdir(parents=True,exist_ok=True);sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
proof=json.loads((base/'measurement-report.json').read_text());assert proof['measurements_verified'] and proof['physical_records']==216 and proof['all2_full4MiB_unchanged_and_reset']
assert sha(base/'artifact-sha256.json')==proof['artifact_index_sha256'];index=json.loads((base/'artifact-sha256.json').read_text())
def bound(p):assert sha(p)==index[str(p.relative_to(base))],p
bound(base/'matrix/manifest.json');manifest=json.loads((base/'matrix/manifest.json').read_text());runner_hash=sha(a.runner);results=[]
assert sha(a.rom)=='9115bbcd03da9f54d3baca5ad94d588a43da54ed332347137ba3dc9010df258b'
for item in manifest:
 clock=item['clock_mhz'];elf=base/'matrix'/item['elf'];bound(elf);assert sha(elf)==item['sha256'];image=elf.read_bytes();pj=base/f'physical-clock{clock}/physical.json';uart=base/f'physical-clock{clock}/uart.bin';bound(pj);bound(uart);hproof=json.loads(pj.read_text());assert hproof['pass'] and hproof['before_matches'] and hproof['after_matches'] and hproof['final_reset'] and not hproof['flash_write_requested'];physical=audit(parse(uart.read_bytes(),image,clock),image);assert physical==hproof['observations'] and sha(uart)==hproof['UART_sha256']
 dest=work/f'clock{clock}';dest.mkdir(exist_ok=True);raw=dest/'native.records';q=subprocess.run(list(map(str,[a.runner.resolve(),elf,a.rom.resolve(),item['snapshot_PC'],raw,1])),capture_output=True,timeout=350);(dest/'stdout').write_bytes(q.stdout);(dest/'stderr').write_bytes(q.stderr);assert q.returncode==0,(q.stdout,q.stderr);native=audit(parse_ram(raw.read_bytes(),image),image);head=Path(str(raw)+'.header.uart');header(head.read_bytes(),clock)
 differences=[];matched=0
 for h,n in zip(physical,native):
  changed={k:[h[k],n[k]] for k in h if h[k]!=n[k]}
  if h['SELECTOR']==0 and h['REPEAT']==0:assert changed=={'CAUSE0':[4,0]}
  else:assert not changed,(clock,h,n,changed)
  matched+=sum(h[k]==n[k] for k in WORDS)
  differences.append({'identity':[h[k] for k in ('TIMER','MODE','DISTANCE','ALIGN','REPEAT')],'all_raw_differences':changed})
 (dest/'raw-differences.json').write_text(json.dumps(differences,indent=2)+chr(10));assert sha(a.runner)==runner_hash
 results.append({'clock_MHz':clock,'records':108,'all_counter_trace_marker_PC_PS_EPS_values_match':True,'raw_words_matching':matched,'raw_words_total':108*32,'initial_boot_cause_differences_retained':1,'ELF_sha256':sha(elf),'physical_UART_sha256':sha(uart),'native_RAM_sha256':sha(raw),'actual_header_UART_sha256':sha(head)})
 print('PASS expiry',clock,'108 records:all raw fields match except one initial CAUSE0;no counter normalization',flush=True)
a.report.write_text(json.dumps({'pass':True,'scope_complete':False,'physical_hardware_accessed':False,'records':216,'raw_words_matching':sum(c['raw_words_matching'] for c in results),'raw_words_total':216*32,'all_counter_samples_match':True,'raw_pending_trace_samples_matching':792,'cases':results,'runner_sha256':runner_hash,'remaining_initial_context_issue':'T376','limits':'Literal-zero counter running/WAITI/masked paths. Other ISR/CSR timing and pending/mixed-source wake cases remain separate.'},indent=2)+chr(10))
