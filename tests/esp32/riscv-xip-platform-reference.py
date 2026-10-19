#!/usr/bin/env python3
"""Primary chip headers/ROM maps constrain native-instrumented XIP startup.
No modeled cache, MMU or C6 CPU behavior is counted as device execution.
"""
import argparse,hashlib,json,re,shutil,struct,subprocess
from pathlib import Path
C=r'''
#include <stdint.h>
#include <stdio.h>
#include "soc/extmem_reg.h"
#include "soc/ext_mem_defs.h"
#include "rom/cache.h"
#include "rom-addresses.h"
#ifdef C6
_Static_assert(_Generic(&Cache_MSPI_MMU_Set,int(*)(uint32_t,uint32_t,uint32_t,uint32_t,uint32_t,uint32_t,uint32_t):1,default:0),"C6 seven-argument map ABI");
#else
_Static_assert(_Generic(&Cache_Ibus_MMU_Set,int(*)(uint32_t,uint32_t,uint32_t,uint32_t,uint32_t,uint32_t):1,default:0),"C3 six-argument map ABI");
#endif
int main(void){uint64_t words[20]={0};
#ifdef C6
words[0]=0x40830000;words[1]=13;words[2]=EXTMEM_L1_CACHE_CTRL_REG;words[3]=EXTMEM_L1_CACHE_SHUT_IBUS|EXTMEM_L1_CACHE_SHUT_DBUS;words[7]=MMU_PAGE_MODE_64KB;
#else
words[0]=0x3fca0000;words[1]=5;words[2]=EXTMEM_ICACHE_CTRL1_REG;words[3]=EXTMEM_ICACHE_SHUT_IBUS|EXTMEM_ICACHE_SHUT_DBUS;
#endif
words[4]=SOC_MMU_IBUS_VADDR_BASE;words[5]=SOC_MMU_DBUS_VADDR_BASE+0x400000;words[6]=SOC_MMU_ENTRY_NUM;
uint64_t rom[]={R_ATTACH,R_BOOT,R_DISABLE,R_ENABLE,R_SPLIT,R_IEND,R_DEND,R_INIT,R_MAP_I,R_MAP_D,R_EFUSE,R_PAGE};for(unsigned i=0;i<12;i++)words[8+i]=rom[i];return fwrite(words,sizeof words,1,stdout)!=1;}
'''
F=r'''
global rv_hal_chip=0;global rv_hal_state=0;global rv_hal_ram_top=0;global rv_hal_data_size=65536;global cfg=0;global checks=0;global calls=0;global cp=1;global dp=1;global cf=0x30000;global df=0x40000;global ps=0;global busy=0;global foreign=0;global bad_chip=0;global fault=0;
global attached=0;global booted=0;global disabled=0;global split=0;global initialized=0;global mapped=0;global enabled=0;global written=0;global pages=0;
fn check(ok){checks=checks+1;if !ok{h_print(2,h_cat3("XIP contract ",h_int(checks)," failed\n"));syscall(60,1,0,0,0,0,0);}return 0;}
fn cv(n){return load64(cfg+n*8);}
fn esp32_state(){if foreign{return 17;}return cv(0);}
fn esp32_irq_save(){let old=ps;ps=ps&~8;return old;}
fn esp32_irq_restore(value){ps=value;return 0;}
fn esp32_external(name){if h_equal(name,"_flex_irom_flash"){return cf;}if h_equal(name,"_flex_irom_pages"){return cp;}if h_equal(name,"_flex_drom_flash"){return df;}check(h_equal(name,"_flex_drom_pages"));return dp;}
fn esp32_load32(address){if address==esp32_state()+16{return busy;}if address==0x40000010{return cv(1)+bad_chip;}check(address==cv(2));return 0xa5a5a5a7;}
fn esp32_store32(address,value){check(!(ps&8)&&disabled&&mapped==1+(dp>0)&&!enabled&&!written);check(address==cv(2)&&value==(0xa5a5a5a7&~cv(3)));written=1;return 0;}
fn esp32_call32(address,a,b,c,d,e,f,g,h){check(!(ps&8));calls=calls+1;
 if address==cv(18)&&cv(18){return 0x12345678;}
 if address==cv(8){check(!attached&&!booted&&!b&&!c&&!d&&!e&&!f&&!g&&!h);if cv(1)==5{check(a==0x12345678);}else{check(!a);}attached=1;return 0;}
 if address==cv(9){check(attached&&!booted&&!disabled);booted=1;return 0;}
 if address==cv(10){check(booted&&!disabled);disabled=1;return 0;}
 if address==cv(19)&&cv(19){check(disabled&&!initialized&&a==cv(7));return 0;}
 if address==cv(12){check(disabled&&!initialized&&a==cv(6)*2&&b==cv(6)*2);split=1;return 0;}
 if address==cv(13){check(split);if fault==1{return 17;}return cv(6)*2;}
 if address==cv(14){check(split);return cv(6)*4;}
 if address==cv(15){check(disabled&&split&&!initialized&&!mapped);initialized=1;let i=0;while i<cv(6){store64(pages+i*8,0);i=i+1;}return 0;}
 if address==cv(16)||address==cv(17){check(disabled&&initialized&&!enabled&&!written);let va=b;let pa=c;let size=d;let count=e;let fixed=f;if cv(1)==13{check(!b);va=c;pa=d;size=e;count=f;fixed=g;}
  check(!a&&size==64&&!fixed&&!h);let expected=cv(4);let flash=cf;let n=cp;if mapped{expected=cv(5);flash=df;n=dp;}check(va==expected&&pa==flash&&count==n&&count>0);
  if fault==2&&!mapped{return 2;}if fault==3&&mapped{return 4;}
  let index=(va&0x7fffff)/65536;let i=0;while i<count{check(index+i<cv(6)&&!load64(pages+(index+i)*8));store64(pages+(index+i)*8,pa/65536+i+1);i=i+1;}mapped=mapped+1;return 0;
 }
 check(address==cv(11)&&disabled&&written&&mapped==1+(dp>0)&&!a&&!enabled);enabled=1;return 0;
}
fn reset(){esp_xip_ready=0;calls=0;attached=0;booted=0;disabled=0;split=0;initialized=0;mapped=0;enabled=0;written=0;cp=2;dp=2;cf=0x30000;df=cf+cp*65536;ps=0;busy=0;foreign=0;bad_chip=0;fault=0;return 0;}
fn main(argc,argv){h_environment(argc,argv);cfg=h_read(load64(argv+8));rv_hal_chip=cv(1);pages=alloc(2048);let c=1;while c<=48{let d=0;while d<=48{if c+d<=61{reset();cp=c;dp=d;df=cf+cp*65536;check(!esp_xip_enable()&&esp_xip_ready&&enabled&&written&&!ps);check(rv_hal_state==cv(0));if cv(0)==0x3fc90000||cv(0)==0x40810000{check(rv_hal_data_size==32768&&rv_hal_ram_top==cv(0)+229376);}let before=calls;check(esp_xip_enable()==-16&&calls==before&&!ps);ps=8;check(esp_xip_enable()==-16&&calls==before&&ps==8);}d=d+1;}c=c+1;}
 let i=0;while i<12{reset();if i==0{cf=0;}if i==1{cp=0;}if i==2{cp=49;}if i==3{dp= -1;}if i==4{dp=49;}if i==5{df=df+1;}if i==6{cp=48;dp=14;df=cf+cp*65536;}if i==7{cp=1<<32;}if i==8{dp=1<<32;}if i==9{cf=0x100030000;}if i==10{df=1<<63;}if i==11{cp= -1;}check(esp_xip_enable()==-22&&!calls&&!ps&&!esp_xip_ready);i=i+1;}
 reset();ps=8;check(esp_xip_enable()==-16&&!calls&&ps==8);reset();busy=1;ps=8;check(esp_xip_enable()==-16&&!calls&&ps==8);reset();foreign=1;check(esp_xip_enable()==-95&&!calls&&!ps);reset();bad_chip=1;check(esp_xip_enable()==-95&&!calls&&!ps);reset();rv_hal_chip=0;check(esp_xip_enable()==-95&&!calls&&!ps);rv_hal_chip=cv(1);
 i=1;while i<=3{reset();fault=i;let error= -5;if i==2{error=2;}if i==3{error=4;}check(esp_xip_enable()==error&&!esp_xip_ready&&!enabled&&!written&&!ps);i=i+1;}
 let out=alloc(8);store64(out,checks);return syscall(1,1,out,8,0,0,0)!=8;
}
'''
def main():
 p=argparse.ArgumentParser();p.add_argument('--compiler',required=True,type=Path);p.add_argument('--reference',required=True,type=Path);p.add_argument('--work',required=True,type=Path);a=p.parse_args();root=Path(__file__).resolve().parents[2];ref=a.reference.resolve();work=a.work.resolve();work.mkdir(parents=True,exist_ok=True);manifest=json.loads((ref/'xip-provenance.json').read_text());rows=[]
 for x in manifest['sources']:assert hashlib.sha256((ref/x['path']).read_bytes()).hexdigest()==x['sha256']
 for chip in [3,6]:
  name='esp32c'+str(chip);w=work/name;inc=w/'include';(inc/'soc').mkdir(parents=True,exist_ok=True);(inc/'rom').mkdir(exist_ok=True)
  for folder in ['include/soc','register/soc']:
   for f in (ref/'components/soc'/name/folder).glob('*.h'):shutil.copy2(f,inc/'soc'/f.name)
  shutil.copy2(ref/f'components/esp_rom/{name}/include/{name}/rom/cache.h',inc/'rom/cache.h');(inc/'esp_assert.h').write_text('#pragma once\n');(inc/'esp_bit_defs.h').write_text('#pragma once\n#define BIT(n) (1U<<(n))\n#define BIT64(n) (1ULL<<(n))\n')
  ld=(ref/f'components/esp_rom/{name}/ld/{name}.rom.ld').read_text();names=['esp_rom_spiflash_attach' if chip==3 else 'spi_flash_attach','ROM_Boot_Cache_Init','Cache_Disable_ICache','Cache_Enable_ICache','Cache_Set_IDROM_MMU_Size','Cache_Get_IROM_MMU_End','Cache_Get_DROM_MMU_End','Cache_MMU_Init','Cache_Ibus_MMU_Set' if chip==3 else 'Cache_MSPI_MMU_Set','Cache_Dbus_MMU_Set' if chip==3 else 'Cache_MSPI_MMU_Set','ets_efuse_get_spiconfig' if chip==3 else None,'MMU_Set_Page_Mode' if chip==6 else None];labels=['ATTACH','BOOT','DISABLE','ENABLE','SPLIT','IEND','DEND','INIT','MAP_I','MAP_D','EFUSE','PAGE'];(inc/'rom-addresses.h').write_text(''.join('#define R_'+label+' '+(re.search(r'\b'+n+r'\s*=\s*(0x[0-9a-fA-F]+)',ld)[1] if n else '0')+'\n' for label,n in zip(labels,names)))
  source=w/'oracle.c';source.write_text(C);oracle=w/'oracle';cmd=['cc','-std=c11','-Wall','-Wextra','-Werror','-I',inc,source,'-o',oracle]
  if chip==6:cmd.insert(1,'-DC6')
  subprocess.run(list(map(str,cmd)),check=True);expected=w/'expected.bin';expected.write_bytes(subprocess.check_output([oracle]));source=w/'model.flex';source.write_text(f'import "{root}/scripts/lib/build.flex";\nimport "{root}/lib/platform/esp32-riscv-xip.flex";\n'+F);binary=w/'model';subprocess.run(['nice','-n','19',str(a.compiler.resolve()),str(source),'-o',str(binary)],check=True)
  for radio in [False,True]:
   data=bytearray(subprocess.check_output([oracle]));
   if radio:struct.pack_into('<Q',data,0,0x3fc90000 if chip==3 else 0x40810000)
   expected=w/('radio.bin' if radio else 'default.bin');expected.write_bytes(data);checks=struct.unpack('<Q',subprocess.check_output([binary,expected],timeout=60))[0];rows.append(dict(chip=name,radio_profile=radio,checks=checks,CPU_execution=False,physical_hardware=False));print(name,'radio' if radio else 'default',checks,'primary cache/MMU contract checks')
 (work/'report.json').write_text(json.dumps(dict(pass_all=True,cases=rows,physical_hardware=False),indent=2)+'\n')
if __name__=='__main__':main()
