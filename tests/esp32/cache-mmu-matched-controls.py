#!/usr/bin/env python3
"""Reject rehashed forged PS-slot pairs before any serial/device child."""
import argparse,hashlib,json,shutil,struct,subprocess,sys
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__)
for name in ('matrix','peer','backup','work','report'):p.add_argument('--'+name,type=Path,required=True)
p.add_argument('--backup-sha256',required=True)
a=p.parse_args();root=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(root/'tests/esp32'));from elf32_symbols import elf32_symbols
work=a.work.resolve();work.mkdir(parents=True,exist_ok=True)
sha=lambda data:hashlib.sha256(data).hexdigest()

def code_offset(image,address):
 offset=struct.unpack_from('<I',image,28)[0];stride,count=struct.unpack_from('<HH',image,42)
 matches=[]
 for i in range(count):
  kind,at,va,pa,length,memory,flags,align=struct.unpack_from('<8I',image,offset+i*stride)
  if kind==1 and va<=address<va+length:matches.append(at+address-va)
 assert len(matches)==1;return matches[0]

def shift_symbol(image,name):
 offset=struct.unpack_from('<I',image,32)[0];stride,count=struct.unpack_from('<HH',image,46)
 sections=[struct.unpack_from('<10I',image,offset+i*stride) for i in range(count)];changed=0
 for section in sections:
  if section[1]!=2:continue
  strings=sections[section[6]];table=image[strings[4]:strings[4]+strings[5]]
  for at in range(section[4],section[4]+section[5],16):
   key,value=struct.unpack_from('<II',image,at);end=table.find(b'\0',key)
   if table[key:end].decode()==name:struct.pack_into('<I',image,at+4,value+3);changed+=1
 assert changed==1

labels=('forged-current-mode','forged-matched-flag','peer-wrong-fault','peer-outside-slot-code','peer-load-address-shift','peer-wrong-NOR','peer-wrong-late-slot','peer-handler-code','peer-data-byte')
results=[]
for label in labels:
 case=work/label;case.mkdir();current=case/'matrix';peer=case/'peer'
 for base,source in ((current,a.matrix),(peer,a.peer)):
  for clock in (40,160):
   group=f'clock{clock}-kind0';dest=base/group;dest.mkdir(parents=True)
   for path in (source/group).iterdir():
    if path.name in ('manifest.json','native.json') or (path.suffix=='.elf' and 'unlinked' not in path.name):shutil.copyfile(path,dest/path.name)
 folder=(current if label.startswith('forged-') else peer)/'clock40-kind0'
 manifest=json.loads((folder/'manifest.json').read_text());native=json.loads((folder/'native.json').read_text())
 if label=='forged-current-mode':
  for c in manifest:c['unmask_near']=2
 elif label=='forged-matched-flag':
  for c in manifest:c['matched_placement']=0
 elif label=='peer-wrong-fault':
  for c in manifest:c['fault']='disabled-data'
 elif label=='peer-wrong-NOR':native['NOR_sha256']='0'*64
 else:
  image_path=folder/manifest[0]['elf'];image=bytearray(image_path.read_bytes());symbols=elf32_symbols(image)
  if label=='peer-outside-slot-code':image[code_offset(image,symbols['cr_tail'])]^=0x10
  elif label=='peer-load-address-shift':shift_symbol(image,'cr_load')
  elif label=='peer-handler-code':image[code_offset(image,symbols['cr_vectors']+0x400)]^=0x10
  elif label=='peer-data-byte':
   from elf32_symbols import elf32_load_segments
   data=next(meta for meta,raw in elf32_load_segments(image) if meta[4]&2 and meta[2])
   image[code_offset(image,data[0])]^=1
  elif label=='peer-wrong-late-slot':
   at=code_offset(image,symbols['cr_unmask_slot']);image[at:at+6]=bytes.fromhex('60e613102000')
  image_path.write_bytes(image);manifest[0]['sha256']=native['cases'][0]['ELF_sha256']=sha(image)
 path=folder/'manifest.json';path.write_text(json.dumps(manifest,indent=2)+'\n');native['manifest_sha256']=sha(path.read_bytes())
 (folder/'native.json').write_text(json.dumps(native,indent=2)+'\n')
 report=case/'outer.json'
 cmd=['python3',root/'tests/esp32/cache-latency-physical.py','--family','mmu','--post-kinds',0,'--unmask-near',1,'--matched-placement',1,'--matrix',current,'--paired-matrix',peer,'--backup',a.backup.resolve(),'--backup-sha256',a.backup_sha256,'--port','/tmp/no-matched-control-port','--espflash','/tmp/no-matched-control-espflash','--report',report]
 q=subprocess.run([str(x) for x in cmd],capture_output=True,timeout=10)
 assert q.returncode==1 and b'AssertionError' in q.stderr and not report.exists(),(label,q.returncode,q.stdout,q.stderr)
 assert not list(current.glob('*/physical-*')),label
 results.append({'control':label,'rehashed_metadata_and_image':True,'rejected_before_device_child':True})
 print('matched pair control',label,'PASS',flush=True)
a.report.write_text(json.dumps({'pass':True,'physical_hardware_touched':False,'controls':results},indent=2)+'\n')
print('PASS:',len(results),'forged matched-code pairs rejected before device access',flush=True)
