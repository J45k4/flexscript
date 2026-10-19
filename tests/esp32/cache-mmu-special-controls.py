#!/usr/bin/env python3
"""Reject rehashed special-register probe forgeries before any device child."""
import argparse,hashlib,json,shutil,struct,subprocess
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__)
for name in ('profiles','peer','backup','work','report'):p.add_argument('--'+name,type=Path,required=True)
p.add_argument('--backup-sha256',required=True)
a=p.parse_args();root=Path(__file__).resolve().parents[2];work=a.work.resolve();work.mkdir(parents=True,exist_ok=True)
sha=lambda b:hashlib.sha256(b).hexdigest()
from elf32_symbols import elf32_symbols
cases=[('SAR-as-PS','sar','ps'),('SAR-as-RSIL','sar','rsil'),('PS-NOP-as-PS-RSYNC','ps-nop','ps'),('RSIL-as-PS','rsil','ps'),('RSIL-as-SAR','rsil','sar'),('SAR-opcode-is-PS','sar','sar'),('NOP-opcode-is-RSYNC','ps-nop','ps-nop'),('RSIL-level-is-one','rsil','rsil')]
results=[]
for label,source_name,forged in cases:
 dest=work/label;dest.mkdir();matrix=dest/'matrix'
 for clock in (40,160):
  group=f'clock{clock}-kind0';source=a.profiles/source_name/'matrix'/group;target=matrix/group;target.mkdir(parents=True)
  for image in source.glob('*.elf'):
   if 'unlinked' not in image.name:shutil.copyfile(image,target/image.name)
  manifest=json.loads((source/'manifest.json').read_text());native=json.loads((source/'native.json').read_text())
  for item in manifest:item['late_op']=forged
  if label in ('SAR-opcode-is-PS','NOP-opcode-is-RSYNC','RSIL-level-is-one'):
   image_path=target/manifest[0]['elf'];image=bytearray(image_path.read_bytes());symbols=elf32_symbols(image)
   address=symbols['cr_unmask_slot']+(3 if label=='NOP-opcode-is-RSYNC' else 0)
   offset=struct.unpack_from('<I',image,28)[0];stride,count=struct.unpack_from('<HH',image,42);positions=[]
   for i in range(count):
    kind,at,va,pa,size,memory,flags,align=struct.unpack_from('<8I',image,offset+i*stride)
    if kind==1 and va<=address and address+3<=va+size:positions.append(at+address-va)
   assert len(positions)==1;at=positions[0]
   image[at:at+3]=bytes.fromhex({'SAR-opcode-is-PS':'60e613','NOP-opcode-is-RSYNC':'102000','RSIL-level-is-one':'706100'}[label])
   image_path.write_bytes(image);manifest[0]['sha256']=native['cases'][0]['ELF_sha256']=sha(image)
  path=target/'manifest.json';path.write_text(json.dumps(manifest,indent=2)+'\n');native['manifest_sha256']=sha(path.read_bytes());(target/'native.json').write_text(json.dumps(native,indent=2)+'\n')
 report=dest/'outer.json';cmd=['python3',root/'tests/esp32/cache-latency-physical.py','--family','mmu','--post-kinds',0,'--unmask-near',2,'--matched-placement',1,'--late-op',forged,'--matrix',matrix,'--paired-matrix',a.peer.resolve(),'--backup',a.backup.resolve(),'--backup-sha256',a.backup_sha256,'--port','/tmp/no-special-op-control-port','--espflash','/tmp/no-special-op-control-espflash','--report',report]
 q=subprocess.run([str(x) for x in cmd],capture_output=True,timeout=10)
 assert q.returncode==1 and b'AssertionError' in q.stderr and not report.exists() and not list(matrix.glob('*/physical-*')),(label,q.returncode,q.stdout,q.stderr)
 results.append({'control':label,'rehashed_manifest_and_native_proof':True,'rejected_before_device_child':True});print('special-op control',label,'PASS',flush=True)
a.report.write_text(json.dumps({'pass':True,'physical_hardware_touched':False,'controls':results},indent=2)+'\n');print('PASS:8 forged special-op profiles rejected before device access',flush=True)
