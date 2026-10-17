#!/usr/bin/env python3
"""Compare unchanged cache IRQ firmware against captured silicon timestamps."""
from pathlib import Path
import json,subprocess,hashlib
import argparse,sys
p=argparse.ArgumentParser(description="Replay artifact-bound cache IRQ timestamp firmware with exact measured elapsed intervals.")
for n in ('checkpoint','runner','rom','nor','work','report'):p.add_argument('--'+n,type=Path,required=True)
p.add_argument('--nor-sha256',required=True);p.add_argument('--checkpoint-index-sha256',required=True);args=p.parse_args()
r=Path(__file__).resolve().parents[2];base=args.checkpoint.resolve();out=args.work.resolve();out.mkdir(parents=True,exist_ok=True)
runner=args.runner.resolve();rom=args.rom.resolve();nor=args.nor.resolve();sh=args.nor_sha256;rows=[]
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
proof=json.loads((base/'report.json').read_text());assert proof['checkpoint_verified']
assert sha(base/'artifact-sha256.json')==args.checkpoint_index_sha256
index=json.loads((base/'artifact-sha256.json').read_text())
def bound(path):assert sha(path)==index[str(path.relative_to(base))],path

def fields(data):
 lines=[line for line in data.splitlines() if line.startswith(b'CACHE LATENCY BUS ')];assert len(lines)==1
 values=lines[0].decode().split();return {k:int(v,16) for k,v in zip(values[2::2],values[3::2])}
for clock in (40,160):
 for kind in (5,6):
  label=f'clock{clock}-kind{kind}';folder=base/'timestamp-matrix'/label;work=out/label
  bound(folder/'manifest.json')
  for item in json.loads((folder/'manifest.json').read_text()):
   elf=folder/item['elf'];bound(elf);assert sha(elf)==item['sha256']
   bound(folder/('physical-DROM' if item['bus']==0 else 'physical-IROM')/f"bus{item['bus']}-mode{item['mode']}.uart")
  cmd=[sys.executable,r/'tests/xtensa/cache-handler-native.py','--family','latency','--runner',runner,'--manifest',folder/'manifest.json','--rom',rom,'--nor',nor,'--nor-sha256',sh,'--work',work,'--report',out/(label+'.json')]
  q=subprocess.run([str(x) for x in cmd],capture_output=True,timeout=220);print(q.stdout.decode(),flush=True);assert q.returncode==0,q.stderr
  for bus in (0,1):
   for mode in range(4):
    file=f'bus{bus}-mode{mode}.uart';n=(work/file).read_bytes();p=(folder/('physical-DROM' if bus==0 else 'physical-IROM')/file).read_bytes();nf,pf=fields(n),fields(p);assert nf.keys()==pf.keys()
    difference={k:[pf[k],nf[k]] for k in pf if pf[k]!=nf[k]};assert set(difference)<={'STARTCC','IRQCC'},(label,file,difference)
    nc=(nf['IRQCC']-nf['STARTCC'])&0xffffffff;pc=(pf['IRQCC']-pf['STARTCC'])&0xffffffff;assert (pc,nc)==(35,35),(label,file,pc,nc)
    rows.append({'clock':clock,'kind':kind,'bus':bus,'alignment':mode,'raw_UART_identical':n==p,'all_register_status_PC_fields_excluding_counter_stamps_match':True,'physical_interval_cycles':pc,'native_interval_cycles':nc,'remaining_cycle_difference':pc-nc,'physical_UART_sha256':hashlib.sha256(p).hexdigest(),'native_UART_sha256':hashlib.sha256(n).hexdigest(),'counter_differences':difference})
args.report.write_text(json.dumps({'observations_verified':True,'scope_complete':False,'physical_hardware_touched':False,'cases':rows,'raw_UART_exact_matches':sum(c['raw_UART_identical'] for c in rows),'semantic_frames_excluding_counter_stamps_matching':32,'exact_cycle_parity':all(c['remaining_cycle_difference']==0 for c in rows),'remaining_cycle_cost_issue':None,'runner_sha256':hashlib.sha256(runner.read_bytes()).hexdigest()},indent=2)+'\n')
print('PASS:32 timedframes preserveallPC/register/status fields;physical/native elapsed intervals match35/35;raw counter origins retained',flush=True)
