#!/usr/bin/env python3
"""Compare actual Flexscript clock adapter writes with pinned Espressif headers."""
import argparse,json,shutil,struct,subprocess
from pathlib import Path

C=r'''
#include <stdint.h>
#include <stdio.h>
#include "soc/timer_group_reg.h"
#ifdef C6
#include "soc/pcr_reg.h"
#else
#include "soc/system_reg.h"
#endif
static uint64_t trace[16][2];static unsigned count;
static uint32_t get(uint32_t addr){for(unsigned i=count;i;i--)if(trace[i-1][0]==addr)return trace[i-1][1];return 0xa5a5a5a5;}
static void put(uint32_t addr,uint32_t value){trace[count][0]=addr;trace[count++][1]=value;}
int main(void){
#ifdef C6
 uint64_t header[]={0x40830000,REG_TIMG_BASE(1),0,0};
 put(PCR_TIMERGROUP1_CONF_REG,(get(PCR_TIMERGROUP1_CONF_REG)&~(PCR_TG1_CLK_EN|PCR_TG1_RST_EN))|PCR_TG1_CLK_EN);
 put(PCR_TIMERGROUP1_TIMER_CLK_CONF_REG,(get(PCR_TIMERGROUP1_TIMER_CLK_CONF_REG)&~(PCR_TG1_TIMER_CLK_SEL_M|PCR_TG1_TIMER_CLK_EN))|PCR_TG1_TIMER_CLK_EN);
 uint32_t config=(40<<TIMG_T0_DIVIDER_S)|TIMG_T0_INCREASE;
#else
 uint64_t header[]={0x3fca0000,REG_TIMG_BASE(1),0,0};
 put(SYSTEM_PERIP_CLK_EN0_REG,get(SYSTEM_PERIP_CLK_EN0_REG)|SYSTEM_TIMERGROUP1_CLK_EN);
 put(SYSTEM_PERIP_RST_EN0_REG,get(SYSTEM_PERIP_RST_EN0_REG)&~SYSTEM_TIMERGROUP1_RST);
 uint32_t config=(40<<TIMG_T0_DIVIDER_S)|TIMG_T0_INCREASE|TIMG_T0_USE_XTAL;
#endif
 put(TIMG_REGCLK_REG(1),get(TIMG_REGCLK_REG(1))|TIMG_TIMER_CLK_IS_ACTIVE);
 put(TIMG_T0CONFIG_REG(1),config);put(TIMG_T0LOADLO_REG(1),0);put(TIMG_T0LOADHI_REG(1),0);put(TIMG_T0LOAD_REG(1),1);put(TIMG_T0CONFIG_REG(1),config|TIMG_T0_EN);
 put(TIMG_T0UPDATE_REG(1),TIMG_T0_UPDATE);put(TIMG_T0UPDATE_REG(1),TIMG_T0_UPDATE);
 header[2]=((uint64_t)(0xff123456&TIMG_T0_HI_V)<<32)|0x89abcdef;header[3]=count;
 fwrite(header,sizeof header,1,stdout);fwrite(trace,sizeof trace[0],count,stdout);return ferror(stdout)?1:0;
}
'''
F=r'''
global expected=0;global writes=0;global registers=0;global checks=0;global ps=0x1888;global busy=0;global timeout=0;global cycle=0;global foreign=0;
fn check(ok){checks=checks+1;if !ok {h_print(2,h_cat3("clock check ",h_int(checks)," failed\n"));syscall(60,1,0,0,0,0,0);}return 0;}
fn esp32_state(){if foreign{return 17;}return load64(expected);}
fn esp32_irq_save(){let old=ps;ps=ps&~8;return old;}
fn esp32_irq_restore(value){ps=value;return 0;}
fn esp32_cycles(){cycle=cycle+500000;return cycle;}
fn esp32_load32(address){let base=load64(expected+8);if address==base {return busy&(1<<31);}if address==base+0x70{return busy&1;}if address==base+0x74{return (busy>>1)&1;}if address==base+12 {if timeout{return 1<<31;}return 0;}if address==base+4{return 0x89abcdef;}if address==base+8{return 0xff123456;}let i=writes;while i {i=i-1;if load64(registers+i*16)==address{return load64(registers+i*16+8);}}return 0xa5a5a5a5;}
fn esp32_store32(address,value){check(writes<load64(expected+24));let row=expected+32+writes*16;check(address==load64(row));check((value&0xffffffff)==load64(row+8));check(!(ps&8));store64(registers+writes*16,address);store64(registers+writes*16+8,value&0xffffffff);writes=writes+1;return 0;}
fn main(argc,argv){h_environment(argc,argv);expected=h_read(load64(argv+8));registers=alloc(1024);
 foreign=1;check(esp_sdk_clock_init()==-95&&esp_sdk_clock_now()==-95&&!writes);foreign=0;
 busy=1<<31;check(esp_sdk_clock_init()==-16&&!writes&&ps==0x1888);busy=1;check(esp_sdk_clock_init()==-16&&!writes&&ps==0x1888);busy=2;check(esp_sdk_clock_init()==-16&&!writes&&ps==0x1888);busy=0;
 check(!esp_sdk_clock_init()&&ps==0x1888);let old=esp32_irq_save();check(esp_sdk_clock_now()==load64(expected+16));timeout=1;check(esp_sdk_clock_now()==-110);esp32_irq_restore(old);check(writes==load64(expected+24)&&ps==0x1888);
 let out=alloc(16);store64(out,checks);store64(out+8,writes);return syscall(1,1,out,16,0,0,0)!=16;}
'''
def main():
 p=argparse.ArgumentParser();p.add_argument('--compiler',required=True);p.add_argument('--reference',type=Path,required=True);p.add_argument('--work',type=Path,required=True);a=p.parse_args();root=Path(__file__).resolve().parents[2];a.work.mkdir(parents=True,exist_ok=True);cases=[]
 for chip in ('esp32c3','esp32c6'):
  w=a.work/chip;inc=w/'include/soc';inc.mkdir(parents=True,exist_ok=True)
  for path in (a.reference/'components/soc'/chip/'register/soc').glob('*.h'):shutil.copyfile(path,inc/path.name)
  shutil.copyfile(a.reference/'components/soc'/chip/'include/soc/soc.h',inc/'soc.h')
  (inc.parent/'esp_assert.h').write_text('#pragma once\n');(inc.parent/'esp_bit_defs.h').write_text('#pragma once\n#define BIT(n) (1U<<(n))\n#define BIT64(n) (1ULL<<(n))\n')
  source=w/'oracle.c';source.write_text(C);obj=w/'oracle';cmd=['cc','-std=c11','-Wall','-Wextra','-Werror','-I',str(inc.parent),str(source),'-o',str(obj)]
  if chip=='esp32c6':cmd.insert(1,'-DC6')
  subprocess.run(cmd,check=True);expected=w/'expected.bin';expected.write_bytes(subprocess.check_output([str(obj)]))
  model=w/'model.flex';model.write_text(f'import "{root}/scripts/lib/build.flex";\nimport "{root}/lib/platform/{chip}.flex";\nimport "{root}/lib/platform/esp32-sdk-riscv-clock.flex";\n'+F);binary=w/'model';subprocess.run([a.compiler,str(model),'-o',str(binary)],check=True);checks,writes=struct.unpack('<QQ',subprocess.check_output([str(binary),str(expected)]));cases.append(dict(chip=chip,checks=checks,exact_writes=writes));print(chip,checks,'clock header checks')
 (a.work/'report.json').write_text(json.dumps(dict(pass_all=True,cases=cases,physical_hardware=False),indent=2)+'\n')
if __name__=='__main__':main()
