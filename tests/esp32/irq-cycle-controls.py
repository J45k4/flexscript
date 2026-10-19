#!/usr/bin/env python3
"""Rehash bad IRQ observations/ELFs and require pre-device rejection."""
import argparse,hashlib,json,shutil,struct,subprocess,sys
from pathlib import Path
from elf32_symbols import elf32_symbols,elf32_mapped
from irq_cycle_protocol import parse_ram,header,record_words
p=argparse.ArgumentParser(description=__doc__)
for name in ('matrix','native-proof','backup','work','report'):p.add_argument('--'+name,type=Path,required=True)
p.add_argument('--backup-sha256',required=True);a=p.parse_args();root=Path(__file__).resolve().parents[2];work=a.work.resolve();work.mkdir(parents=True,exist_ok=True);sha=lambda b:hashlib.sha256(b).hexdigest()
positive=json.loads(a.native_proof.read_text());original_manifest=json.loads((a.matrix/'manifest.json').read_text());assert positive['pass'] and positive['images']==original_manifest and positive['native_records']==768
for f,h in positive['source_sha256'].items():assert sha((root/f).read_bytes())==h,('positive build proof is stale',f)
for item in original_manifest:
 image=(a.matrix/item['elf']).read_bytes();raw=(a.matrix/item['native_records']).read_bytes();head=(a.matrix/item['native_header']).read_bytes();assert sha(image)==item['sha256'] and sha(raw)==item['native_records_sha256'] and sha(head)==item['native_header_sha256'];assert len(parse_ram(raw,image))==384;header(head,item['clock_mhz'])
labels=('zero-entry-interval','zero-return-interval','counter-order','missing-IRQ','source-disabled','wrong-before-mask','missing-EXCM','EXCM-after-return','wrong-original-EPC','wrong-resume','wrong-vector-base','software-source-not-cleared','duplicate-repeat','truncated-records','wrong-clock-header','wrong-RFE','wrong-trigger','wrong-handler-prefix','wrong-vector-target','wrong-entry-counter')
if positive['family']=='IRQ7-entry-return-v2-marker':labels+=('wrong-marker-value','wrong-followup-opcode','missing-marker-store','wrong-marker-init','wrong-marker-format')
def patch_elf(path,address,replacement):
 image=bytearray(path.read_bytes());offset=struct.unpack_from('<I',image,28)[0];stride,count=struct.unpack_from('<HH',image,42);positions=[]
 for i in range(count):
  kind,at,va,pa,size,memory,flags,align=struct.unpack_from('<8I',image,offset+i*stride)
  if kind==1 and va<=address and address+len(replacement)<=va+size:positions.append(at+address-va)
 assert len(positions)==1;at=positions[0];image[at:at+len(replacement)]=replacement;path.write_bytes(image);return sha(image)
results=[]
for label in labels:
 folder=work/label;folder.mkdir();matrix=folder/'matrix';manifest=json.loads(json.dumps(original_manifest));proof=json.loads(json.dumps(positive))
 for item in manifest:
  for key in ('elf','native_records','native_header'):
   dest=matrix/item[key];dest.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(a.matrix/item[key],dest)
 item=manifest[0];records=matrix/item['native_records'];data=bytearray(records.read_bytes());stride=len(record_words((matrix/item['elf']).read_bytes()))*4
 def get(word):return struct.unpack_from('<I',data,word*4)[0]
 def put(word,value):struct.pack_into('<I',data,word*4,value&0xffffffff)
 if label=='zero-entry-interval':put(1,get(0))
 elif label=='zero-return-interval':put(3,get(2))
 elif label=='counter-order':put(2,get(1)-1)
 elif label=='missing-IRQ':put(10,0)
 elif label=='source-disabled':put(8,0)
 elif label=='wrong-before-mask':put(4,get(4)|15)
 elif label=='missing-EXCM':put(5,get(5)&~16)
 elif label=='EXCM-after-return':put(13,get(13)|16)
 elif label=='wrong-original-EPC':put(6,0x40080000)
 elif label=='wrong-resume':put(7,get(7)+1)
 elif label=='wrong-vector-base':put(11,0x40080000)
 elif label=='software-source-not-cleared':put(14,get(14)|128)
 elif label=='duplicate-repeat':data[:stride]=data[stride:stride*2]
 elif label=='truncated-records':data=data[:-stride]
 elif label=='wrong-marker-value':put(16,17)
 elif label=='wrong-marker-format':
  proof['family']='IRQ7-entry-return-v1';proof['record_words']=16
  for row in manifest:row['record_words']=16
 elif label=='wrong-clock-header':
  path=matrix/item['native_header'];head=path.read_bytes().replace(b'SOURCE 0000000000000000',b'SOURCE 0000000000000001');path.write_bytes(head);item['native_header_sha256']=sha(head)
 else:
  path=matrix/item['elf'];image=path.read_bytes();symbols=elf32_symbols(image)
  if label=='wrong-RFE':address=symbols['iq_rfe'];replacement=bytes.fromhex('f02000')
  elif label=='wrong-trigger':address=symbols['iq_trigger_0_0_0_0'];replacement=bytes.fromhex('b0e313')
  elif label=='wrong-handler-prefix':address=symbols['iq_handler_2'];replacement=bytes.fromhex('12c1b4')
  elif label=='wrong-vector-target':
   address=symbols['iq_vectors_1']+0x300;replacement=(int.from_bytes(elf32_mapped(image,address,3),'little')+64).to_bytes(3,'little')
  elif label=='wrong-entry-counter':address=symbols['iq_counter_1'];replacement=bytes.fromhex('70ea03')
  elif label=='wrong-followup-opcode':address=symbols['iq_trigger_0_0_0_0']+3;replacement=bytes.fromhex('a2ca02')
  elif label=='missing-marker-store':address=symbols['iq_marker_capture'];replacement=bytes.fromhex('f02000')
  else:address=symbols['iq_marker_zero_0_0_0_0'];replacement=bytes.fromhex('b2a000')
  item['sha256']=patch_elf(path,address,replacement)
 records.write_bytes(data);item['native_records_sha256']=sha(data);(matrix/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n');proof['images']=manifest;native=folder/'native.json';native.write_text(json.dumps(proof,indent=2)+'\n')
 called=folder/'fake-tool-called';flash=folder/'fake-espflash';flash.write_text('#!/usr/bin/env python3\nfrom pathlib import Path\nPath('+repr(str(called))+').write_text("called")\nraise SystemExit(4)\n');flash.chmod(0o700);stub=folder/'serial-stub';stub.write_bytes(b'');port=folder/'usb-1a86_USB_Serial-if00-port0';port.symlink_to(stub);dest=folder/'physical'
 cmd=[sys.executable,root/'tests/esp32/irq-cycle-physical.py','--matrix',matrix,'--native-proof',native,'--clock',40,'--backup',a.backup.resolve(),'--backup-sha256',a.backup_sha256,'--port',port,'--espflash',flash,'--work',dest];q=subprocess.run([str(x) for x in cmd],capture_output=True,timeout=20)
 rejected=q.returncode==1 and b'AssertionError' in q.stderr and not called.exists() and not dest.exists();results.append({'control':label,'rehashed_manifest_and_native_proof':True,'rejected_before_device_child':rejected,'fake_tool_called':called.exists()});(folder/'stderr').write_bytes(q.stderr);print(label,'PASS' if rejected else 'ESCAPED PREFLIGHT',flush=True)
report={'pass':all(c['rejected_before_device_child'] for c in results),'positive_native_records_checked':768,'physical_hardware_touched':False,'controls':results};a.report.write_text(json.dumps(report,indent=2)+'\n');assert report['pass'],'forged IRQ evidence reached fake tool';print(f'PASS:{len(results)} rehashed IRQ evidence mutations reject before any device child',flush=True)
