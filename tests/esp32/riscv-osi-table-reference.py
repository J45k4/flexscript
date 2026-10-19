#!/usr/bin/env python3
"""Primary C offsetof/size plus instrumented native OSI table construction."""
import argparse,hashlib,json,re,struct,subprocess
from pathlib import Path

def symbol_bytes(path,name):
 raw=path.read_bytes();off=struct.unpack_from('<I',raw,32)[0];count=struct.unpack_from('<H',raw,48)[0];sections=[struct.unpack_from('<10I',raw,off+i*40) for i in range(count)]
 for section in sections:
  if section[1]!=2:continue
  strings=sections[section[6]];pool=raw[strings[4]:strings[4]+strings[5]]
  for at in range(section[4],section[4]+section[5],16):
   n,value,size,info,other,index=struct.unpack_from('<IIIBBH',raw,at)
   if pool[n:pool.index(0,n)].decode()==name:
    target=sections[index];return raw[target[4]+value:target[4]+value+size]
 raise AssertionError(name)

def main():
 p=argparse.ArgumentParser();p.add_argument('--compiler',required=True,type=Path);p.add_argument('--reference',required=True,type=Path);p.add_argument('--work',required=True,type=Path);a=p.parse_args();root=Path(__file__).resolve().parents[2];ref=a.reference.resolve();w=a.work.resolve();w.mkdir(parents=True,exist_ok=True);cases=[];controls=[]
 def run(cmd,reject=False):
  r=subprocess.run(list(map(str,cmd)),cwd=root,capture_output=True,timeout=60);assert (r.returncode!=0 if reject else r.returncode==0),(cmd,r.stdout,r.stderr);return r
 source=(root/'lib/platform/esp32-riscv-radio-osi.flex').read_text();legacy=(root/'lib/platform/esp32s3-radio-os.flex').read_text();mapping={name:value for off,value,name in re.findall(r'    esp32_store32\(table\+(\d+),(.+)\); // (\w+)',legacy)}
 mapping.update(_regdma_link_set_write_wait_content='esp32_callback32(esp_radio_cb_retention_fault)',_sleep_retention_find_link_by_id='esp32_callback32(esp_radio_cb_retention_fault)',_wifi_disable_ac_ax='esp32_callback32(esp_radio_cb_no_wifi6_disable)',_wifi_bb_sleep_retention_attach='esp32_callback32(esp_radio_cb_no_retention)',_wifi_bb_sleep_retention_detach='esp32_callback32(esp_radio_cb_no_retention)',_wifi_mac_sleep_retention_attach='esp32_callback32(esp_radio_cb_no_retention)',_wifi_mac_sleep_retention_detach='esp32_callback32(esp_radio_cb_no_retention)')
 names=sorted(set(re.findall(r'esp32_callback32\((\w+)\)',source)));ids={name:0x1000+i*4 for i,name in enumerate(names)}
 def instrument(text):return re.sub(r'esp32_callback32\((\w+)\)',lambda m:str(ids[m[1]]),text)
 for chip in [3,6]:
  d=w/f'c{chip}';d.mkdir(exist_ok=True);header=ref/'osi-primary/vendor/c/include/esp_private/wifi_os_adapter.h';(d/'wifi_os_adapter.h').write_bytes(header.read_bytes());(d/'sdkconfig.h').write_text(f'#define CONFIG_IDF_TARGET_ESP32C{chip} 1\n#define CONFIG_SOC_WIFI_HE_SUPPORT {int(chip==6)}\n');primary=(ref/f'vendor/esp32c{chip}/include.rs').read_text();fields=re.findall(r'^    pub (\w+):',re.search(r'pub struct wifi_osi_funcs_t \{(.*?)\n\}',primary,re.S)[1],re.M);c=d/'oracle.c';c.write_text('#include <stddef.h>\n#include "wifi_os_adapter.h"\nconst unsigned abi_size=sizeof(wifi_osi_funcs_t);\nconst unsigned abi_offsets[]={'+','.join('offsetof(wifi_osi_funcs_t,'+n+')' for n in fields)+'};\n');obj=d/'oracle.o';run(['clang','--target=riscv32','-mabi=ilp32','-march=rv32imc','-c',c,'-o',obj]);size=struct.unpack('<I',symbol_bytes(obj,'abi_size'))[0];offsets=struct.unpack('<'+'I'*len(fields),symbol_bytes(obj,'abi_offsets'));assert size==len(fields)*4 and offsets==tuple(range(0,size,4));values=[]
  for field in fields:
   expected=mapping[field];m=re.fullmatch(r'esp32_callback32\((\w+)\)',expected);values.append(ids[m[1]] if m else int(expected,0))
  expected=d/'expected.bin';expected.write_bytes(struct.pack('<II',size,len(fields))+b''.join(struct.pack('<II',off,value) for off,value in zip(offsets,values))+bytes(8));f=r'''
global expected=0;global table=0;global writes=0;
fn esp32_state(){return rv_hal_state;}fn esp32_cycles(){return 0;}fn esp32_irq_save(){return 0;}fn esp32_irq_restore(a){return 0;}fn esp32_load32(a){return 0;}
fn esp32_call32(a,b,c,d,e,f,g,h,i){return 0;}
fn esp32_store32(address,value){let i=0;while i<4{store8(address+i,value>>(i*8));i=i+1;}writes=writes+1;return 0;}
fn main(argc,argv){h_environment(argc,argv);expected=h_read(load64(argv+8));rv_hal_chip=CHIP;let size=load64(expected)&4294967295;table=alloc(size+32);let i=0;while i<size+32{store8(table+i,165);i=i+1;}if esp_radio_os_size()!=size || esp_radio_nvs_offset()!=268{return 1;}esp_radio_os_build(table+16);if writes!=size/4{return 2;}i=0;while i<size/4{let row=expected+8+i*8;let offset=load64(row)&4294967295;let want=load64(row+4)&4294967295;if (load64(table+16+offset)&4294967295)!=want{return 3;}i=i+1;}i=0;while i<16{if load8(table+i)!=165 || load8(table+size+16+i)!=165{return 4;}i=i+1;}return 0;}
'''.replace('CHIP','5' if chip==3 else '13')
  mutations=[None]
  if chip==3:mutations += [('wrong-version','store32(table+0,9)','store32(table+0,8)'),('wrong-magic','3735928495','3735928494'),('wrong-NVS-offset','return 268;','return 276;')]
  else:mutations += [('missing-C6-shift','shift=8;','shift=0;'),('wrong-C6-retention-slot','table+488','table+484')]
  for mutation in mutations:
   name=mutation[0] if mutation else 'canonical';text=source
   if mutation:assert mutation[1] in text;text=text.replace(mutation[1],mutation[2])
   module=d/(name+'.flex');module.write_text(f'import "{root}/scripts/lib/build.flex";\nimport "{root}/lib/platform/esp32c{chip}.flex";\n'+f+'\n'+instrument(text));binary=d/name;run([a.compiler.resolve(),module,'-o',binary]);result=run([binary,expected],reject=mutation is not None)
   row=dict(chip=chip,case=name,CPU_execution=False,callback_ID_instrumentation=True,physical_hardware=False,result=result.returncode)
   if mutation:row['detected']=True;controls.append(row)
   else:row.update(primary_fields=len(fields),primary_size=size,primary_C_header_sha256=hashlib.sha256(header.read_bytes()).hexdigest());cases.append(row)
 report=dict(pass_all=True,cases=cases,detected_defects=controls,primary_fields=sum(x['primary_fields'] for x in cases),C6_CPU_execution=False,physical_hardware=False);(w/'report.json').write_text(json.dumps(report,indent=2)+'\n');print('PASS:',report['primary_fields'],'primary OSI field layouts and',len(controls),'detected table defects')
if __name__=='__main__':main()
