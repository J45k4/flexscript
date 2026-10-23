#!/usr/bin/env python3
"""Read every actual generated API byte through bounded VM RPC pages, with all grants denied."""
import argparse,json,re,shutil,subprocess,tempfile
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--out',type=Path,required=True);a=p.parse_args();out=a.out.resolve();qemu=shutil.which('qemu-aarch64-static') or shutil.which('qemu-aarch64')
s=(out/'engine-generated.flex').read_text();full=json.loads(re.search(r'fn ca_hardware_api\(\)\{return (".*");\}',s).group(1)).encode();index=json.loads(re.search(r'fn ca_hardware_index\(\)\{return (".*");\}',s).group(1)).encode();checks=[]
with tempfile.TemporaryDirectory(prefix='hardware-reference-',dir=out) as directory:
 root=Path(directory);config=dict(workspace_file=str(root/'agent.flexdb'),permissions={key:False for key in ['internet','files_read','files_write','db_read','db_write','history','workers','nfc','secure_element','bluetooth','network']})
 def vm(source):
  r=subprocess.run([qemu,str(out/'native-test'),'3',str(root)],input=json.dumps(dict(config=config,source=source,history=[])).encode(),capture_output=True,timeout=40);assert r.returncode==0,(r.returncode,r.stderr[:500]);o=json.loads(r.stdout);assert o['state']=='continue' and o['exit_code']==0,o;return o['stdout'].encode()
 actual=vm('fn main(){let v=hardware_api();if db_kind(v)!=2{return 1;}db_io(0,1,db_word(v),db_bytes(v));return 0;}');assert actual==index and len(actual)<=32768
 checks.append('the compact function index is returned intact through the actual VM with every capability denied')
 actual=bytearray()
 for offset in range(0,len(full),4096):
  size=min(4096,len(full)-offset);next_offset=offset+size if offset+size<len(full) else -1
  page=vm('fn main(){let p=hardware_api_page('+str(offset)+',4096);if !p || db_word(device_field(p,"total"))!='+str(len(full))+' || db_word(device_field(p,"next"))!='+str(next_offset)+'{return 1;}let v=device_field(p,"text");db_io(0,1,db_word(v),db_bytes(v));return 0;}');assert page==full[offset:offset+size];actual.extend(page)
 assert bytes(actual)==full
 checks.append('every detailed reference byte is readable via bounded pages, including the full NFC/OMAPI contracts')
 actual=vm('fn main(){let p=hardware_api_page(0,32768);if !p{return 1;}let v=device_field(p,"text");if db_bytes(v)!=32768{return 2;}db_io(0,1,db_word(v),db_bytes(v));return 0;}');assert actual==full[:32768]
 checks.append('a maximum32768-byte reference page survives the complete typed RPC frame without truncation')
 vm('fn main(){if hardware_api_page(-1,100) || hardware_api_page(0,0) || hardware_api_page(0,32769) || hardware_api_page('+str(len(full)+1)+',10){return 1;}let e=device_error();if !worker_equal(db_word(db_at(e,0)),"invalid_argument"){return 2;}let end=hardware_api_page('+str(len(full))+',10);if db_word(device_field(end,"next"))!=-1 || db_bytes(device_field(end,"text")){return 3;}return 0;}')
 checks.append('invalid page bounds are structured errors and an exact EOF returns an empty final page')
for text in checks:print('PASS',text)
(out/'hardware-reference-report.json').write_text(json.dumps(dict(checks=checks,reference_bytes=len(full),index_bytes=len(index)),indent=2)+'\n')
