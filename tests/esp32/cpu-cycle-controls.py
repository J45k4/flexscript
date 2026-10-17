#!/usr/bin/env python3
"""Rehash bad cycle evidence and require rejection before an instrumented fake tool."""
import argparse,hashlib,json,shutil,struct,subprocess,sys
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__)
for name in ('matrix','native-proof','backup','work','report'):p.add_argument('--'+name,type=Path,required=True)
p.add_argument('--backup-sha256',required=True)
a=p.parse_args();root=Path(__file__).resolve().parents[2];work=a.work.resolve();work.mkdir(parents=True,exist_ok=True);sha=lambda b:hashlib.sha256(b).hexdigest()
from elf32_symbols import elf32_symbols
labels=('zero-interval','incoherent-counter-samples','EXCM-set','IRQ-enabled','wrong-register-result','swapped-PS-rows','truncated-records','wrong-GNU-opcode','wrong-clock-header','wrong-pattern-set','wrong-timing-profile')
if json.loads(a.native_proof.read_text()).get('pattern_set')=='controlflow':labels+=('wrong-leaf-body','wrong-leaf-target','wrong-branch-condition')
results=[]
def rewrite_elf(path,address,replacement):
 image=bytearray(path.read_bytes());offset=struct.unpack_from('<I',image,28)[0];stride,count=struct.unpack_from('<HH',image,42);positions=[]
 for i in range(count):
  kind,at,va,pa,size,memory,flags,align=struct.unpack_from('<8I',image,offset+i*stride)
  if kind==1 and va<=address and address+len(replacement)<=va+size:positions.append(at+address-va)
 assert len(positions)==1;at=positions[0];image[at:at+len(replacement)]=replacement;path.write_bytes(image);return sha(image)

for label in labels:
 folder=work/label;folder.mkdir();matrix=folder/'matrix';manifest=json.loads((a.matrix/'manifest.json').read_text());proof=json.loads(a.native_proof.read_text())
 for c in manifest:
  for key in ('elf','native_records','native_header'):
   src=a.matrix/c[key];dest=matrix/c[key];dest.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(src,dest)
 c=manifest[0];records=matrix/c['native_records'];data=bytearray(records.read_bytes())
 if label=='zero-interval':struct.pack_into('<I',data,16,0)
 elif label=='incoherent-counter-samples':struct.pack_into('<I',data,8,(struct.unpack_from('<I',data,8)[0]+1)&0xffffffff)
 elif label=='EXCM-set':
  for at in (20,24):struct.pack_into('<I',data,at,struct.unpack_from('<I',data,at)[0]|16)
 elif label=='IRQ-enabled':struct.pack_into('<I',data,36,1)
 elif label=='wrong-register-result':struct.pack_into('<I',data,28,1)
 elif label=='swapped-PS-rows':data[:80]=data[40:80]+data[:40]
 elif label=='truncated-records':data=data[:-40]
 elif label=='wrong-GNU-opcode':
  path=matrix/c['elf'];image=bytearray(path.read_bytes());symbols=elf32_symbols(image);address=symbols['cc_begin_0_1_0']+3
  offset=struct.unpack_from('<I',image,28)[0];stride,count=struct.unpack_from('<HH',image,42);positions=[]
  for i in range(count):
   kind,at,va,pa,size,memory,flags,align=struct.unpack_from('<8I',image,offset+i*stride)
   if kind==1 and va<=address and address+3<=va+size:positions.append(at+address-va)
  assert len(positions)==1;at=positions[0];image[at:at+3]=bytes.fromhex('72c701');path.write_bytes(image);c['sha256']=sha(image)
 elif label in ('wrong-leaf-body','wrong-leaf-target','wrong-branch-condition'):
  from cpu_controlflow_oracle import control_target_literal
  from elf32_symbols import elf32_mapped
  path=matrix/c['elf'];image=path.read_bytes();symbols=elf32_symbols(image)
  if label=='wrong-leaf-body':address=symbols['cc_full_leaf'];replacement=bytes.fromhex('f02000')
  elif label=='wrong-leaf-target':address=control_target_literal(image,symbols['cc_target_9_1_0']);replacement=struct.pack('<I',symbols['cc_fast_leaf'])
  else:
   address=symbols['cc_begin_2_1_0']+3;replacement=(int.from_bytes(elf32_mapped(image,address,3),'little')^0x40).to_bytes(3,'little')
  c['sha256']=rewrite_elf(path,address,replacement)
 elif label=='wrong-clock-header':
  path=matrix/c['native_header'];raw=path.read_bytes();raw=raw.replace(b'SOURCE 0000000000000000',b'SOURCE 0000000000000001');path.write_bytes(raw);c['native_header_sha256']=sha(raw)
 if label=='wrong-pattern-set':
  other='basic' if proof.get('pattern_set','basic')=='followers' else 'followers'
  proof['pattern_set']=other
  for entry in manifest:entry['pattern_set']=other
 if label=='wrong-timing-profile':
  other='functional' if proof.get('timing_profile','functional')=='lx6' else 'lx6'
  proof['timing_profile']=other;proof['one_cycle_per_instruction_baseline_verified']=other=='functional';proof['measured_LX6_timing_verified']=other=='lx6'
 records.write_bytes(data);c['native_records_sha256']=sha(data)
 (matrix/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n');proof['images']=manifest;native=folder/'native.json';native.write_text(json.dumps(proof,indent=2)+'\n')
 called=folder/'fake-tool-called';flash=folder/'fake-espflash';flash.write_text('#!/usr/bin/env python3\nfrom pathlib import Path\nPath('+repr(str(called))+').write_text("called")\nraise SystemExit(4)\n');flash.chmod(0o700)
 stub=folder/'serial-stub';stub.write_bytes(b'');port=folder/'usb-1a86_USB_Serial-if00-port0';port.symlink_to(stub)
 dest=folder/'physical';cmd=['python3',root/'tests/esp32/cpu-cycle-physical.py','--matrix',matrix,'--native-proof',native,'--clock',40,'--backup',a.backup.resolve(),'--backup-sha256',a.backup_sha256,'--port',port,'--espflash',flash,'--work',dest]
 q=subprocess.run([str(x) for x in cmd],capture_output=True,timeout=15)
 rejected=q.returncode==1 and b'AssertionError' in q.stderr and not called.exists() and not dest.exists()
 results.append({'control':label,'rehashed_manifest_and_native_proof':True,'rejected_before_device_child':rejected,'fake_tool_called':called.exists()});print(label,'PASS' if rejected else 'ESCAPED PREFLIGHT',flush=True)
report={'pass':all(c['rejected_before_device_child'] for c in results),'physical_hardware_touched':False,'controls':results};a.report.write_text(json.dumps(report,indent=2)+'\n');assert report['pass'],'a forged input reached the instrumented fake device tool'
print(f'PASS:{len(results)} rehashed cycle-evidence mutations rejected before any device child',flush=True)
