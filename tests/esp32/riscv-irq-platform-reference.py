#!/usr/bin/env python3
"""Pinned Espressif C-header oracle for the actual RISC-V IRQ/timer adapters."""
import argparse,json,re,shutil,struct,subprocess
from pathlib import Path
C=r'''
#include <stdint.h>
#include <stdio.h>
#include "soc/interrupts.h"
#include "soc/timer_group_reg.h"
#ifdef C6
#include "soc/pcr_reg.h"
#include "soc/plic_reg.h"
#include "soc/intpri_reg.h"
#include "soc/interrupt_matrix_reg.h"
#else
#include "soc/system_reg.h"
#include "soc/interrupt_core0_reg.h"
#endif
static uint64_t trace[256][2];static unsigned count;
static uint32_t get(uint32_t a){for(unsigned i=count;i;i--)if(trace[i-1][0]==a)return trace[i-1][1];return 0xa5a5a5a5;}
static void put(uint32_t a,uint32_t v){trace[count][0]=a;trace[count++][1]=v;}
static void update(uint32_t a,uint32_t m,uint32_t v){put(a,(get(a)&~m)|(v&m));}
int main(void){
#ifdef C6
 uint64_t header[]={0x40830000,DR_REG_INTMTX_BASE,ETS_MAX_INTR_SOURCE,ETS_FROM_CPU_INTR0_SOURCE,PLIC_MXINT1_PRI_REG,PLIC_MXINT7_PRI_REG,REG_TIMG_BASE(0),REG_TIMG_BASE(1),ETS_TG0_T0_LEVEL_INTR_SOURCE,ETS_TG1_T0_LEVEL_INTR_SOURCE,PLIC_MXINT_ENABLE_REG,PLIC_EMIP_STATUS_REG,INTPRI_CPU_INTR_FROM_CPU_0_REG,0};
#else
 uint64_t header[]={0x3fca0000,DR_REG_INTERRUPT_CORE0_BASE,ETS_MAX_INTR_SOURCE,ETS_FROM_CPU_INTR0_SOURCE,INTERRUPT_CORE0_CPU_INT_PRI_1_REG,INTERRUPT_CORE0_CPU_INT_PRI_7_REG,REG_TIMG_BASE(0),REG_TIMG_BASE(1),ETS_TG0_T0_LEVEL_INTR_SOURCE,ETS_TG1_T0_LEVEL_INTR_SOURCE,INTERRUPT_CORE0_CPU_INT_ENABLE_REG,INTERRUPT_CORE0_CPU_INT_EIP_STATUS_REG,SYSTEM_CPU_INTR_FROM_CPU_0_REG,0};
#endif
 for(unsigned group=0;group<2;group++)for(unsigned xtal=0;xtal<2;xtal++){
  uint32_t config=(40<<TIMG_T0_DIVIDER_S)|TIMG_T0_INCREASE;
#ifdef C6
  uint32_t bus=PCR_TIMERGROUP0_CONF_REG+group*(PCR_TIMERGROUP1_CONF_REG-PCR_TIMERGROUP0_CONF_REG);
  uint32_t clock=PCR_TIMERGROUP0_TIMER_CLK_CONF_REG+group*(PCR_TIMERGROUP1_TIMER_CLK_CONF_REG-PCR_TIMERGROUP0_TIMER_CLK_CONF_REG);
  update(bus,PCR_TG0_CLK_EN|PCR_TG0_RST_EN,PCR_TG0_CLK_EN);
  update(clock,PCR_TG0_TIMER_CLK_SEL_M|PCR_TG0_TIMER_CLK_EN,((xtal?0:1)<<PCR_TG0_TIMER_CLK_SEL_S)|PCR_TG0_TIMER_CLK_EN);
#else
  uint32_t bit=group?SYSTEM_TIMERGROUP1_CLK_EN:SYSTEM_TIMERGROUP_CLK_EN;
  update(SYSTEM_PERIP_CLK_EN0_REG,bit,bit);update(SYSTEM_PERIP_RST_EN0_REG,bit,0);
  if(xtal)config|=TIMG_T0_USE_XTAL;
#endif
  update(TIMG_REGCLK_REG(group),TIMG_TIMER_CLK_IS_ACTIVE,TIMG_TIMER_CLK_IS_ACTIVE);
  put(TIMG_T0CONFIG_REG(group),config);put(TIMG_T0LOADLO_REG(group),0);put(TIMG_T0LOADHI_REG(group),0);put(TIMG_T0LOAD_REG(group),1);
  put(TIMG_T0LOADLO_REG(group),0x89abcdef);put(TIMG_T0LOADHI_REG(group),0x123456);put(TIMG_T0LOAD_REG(group),1);
  put(TIMG_T0ALARMLO_REG(group),0x76543210);put(TIMG_T0ALARMHI_REG(group),0x234567);
  update(TIMG_INT_ENA_TIMERS_REG(group),TIMG_T0_INT_ENA,TIMG_T0_INT_ENA);
  update(TIMG_T0CONFIG_REG(group),TIMG_T0_AUTORELOAD|TIMG_T0_ALARM_EN,TIMG_T0_AUTORELOAD|TIMG_T0_ALARM_EN);
  update(TIMG_T0CONFIG_REG(group),TIMG_T0_EN,TIMG_T0_EN);
  put(TIMG_INT_CLR_TIMERS_REG(group),TIMG_T0_INT_CLR);update(TIMG_T0CONFIG_REG(group),TIMG_T0_ALARM_EN,TIMG_T0_ALARM_EN);
  update(TIMG_T0CONFIG_REG(group),TIMG_T0_EN,0);
 }
 header[13]=count;fwrite(header,sizeof header,1,stdout);fwrite(trace,sizeof trace[0],count,stdout);return ferror(stdout)?1:0;
}
'''
F=r'''
global expected=0;global registers=0;global writes=0;global checks=0;global ps=0x1888;
fn check(ok){checks=checks+1;if !ok{h_print(2,h_cat3("IRQ/timer oracle check ",h_int(checks)," failed\n"));syscall(60,1,0,0,0,0,0);}return 0;}
fn esp32_state(){return load64(expected);}
fn esp32_cycles(){return 0;}
fn esp32_irq_save(){let old=ps;ps=ps&~8;return old;}
fn esp32_irq_restore(value){ps=value;return 0;}
fn esp32_irq_enabled(){return 0;}
fn esp32_irq_mask(value){return 0;}
fn esp32_irq_clear(value){return 0;}
fn esp32_call(function,value){return 0;}
fn esp32_load32(address){let i=writes;while i{i=i-1;if load64(registers+i*16)==address{return load64(registers+i*16+8);}}return 0xa5a5a5a5;}
fn esp32_store32(address,value){check(writes<load64(expected+104));let row=expected+112+writes*16;check(address==load64(row));check((value&4294967295)==load64(row+8));check(!(ps&8));store64(registers+writes*16,address);store64(registers+writes*16+8,value&4294967295);writes=writes+1;return 0;}
fn main(argc,argv){h_environment(argc,argv);expected=h_read(load64(argv+8));registers=alloc(8192);
 check(esp_irq_matrix()==load64(expected+8));check(esp_irq_sources()==load64(expected+16));check(esp_irq_soft_source()==load64(expected+24));check(esp_irq_priority(1)==load64(expected+32));check(esp_irq_priority(7)==load64(expected+40));check(esp_timer_base(0)==load64(expected+48));check(esp_timer_base(2)==load64(expected+56));check(esp_timer_source(0)==load64(expected+64));check(esp_timer_source(2)==load64(expected+72));
 let group=0;while group<2 {let xtal=0;while xtal<2 {let id=group*2;check(!esp_timer_init(id,40,xtal));check(!esp_timer_set_words(id,0x89abcdef,0x123456));check(!esp_timer_alarm_words(id,0x76543210,0x234567,1));check(!esp_timer_start(id));check(!esp_timer_ack(id,1));check(!esp_timer_stop(id));check(ps==0x1888);xtal=xtal+1;}group=group+1;}
 check(writes==load64(expected+104));let out=alloc(16);store64(out,checks);store64(out+8,writes);return syscall(1,1,out,16,0,0,0)!=16;}
'''
def main():
 p=argparse.ArgumentParser();p.add_argument('--compiler',required=True);p.add_argument('--reference',type=Path,required=True);p.add_argument('--work',required=True,type=Path);a=p.parse_args();root=Path(__file__).resolve().parents[2];a.work.mkdir(parents=True,exist_ok=True);cases=[]
 for chip in ('esp32c3','esp32c6'):
  w=a.work/chip;inc=w/'include/soc';inc.mkdir(parents=True,exist_ok=True)
  for base in ('register/soc','include/soc'):
   for f in (a.reference/'components/soc'/chip/base).glob('*.h'):shutil.copyfile(f,inc/f.name)
  (inc.parent/'esp_assert.h').write_text('#pragma once\n');(inc.parent/'esp_bit_defs.h').write_text('#pragma once\n#define BIT(n) (1U<<(n))\n#define BIT64(n) (1ULL<<(n))\n')
  source=w/'oracle.c';source.write_text(C);oracle=w/'oracle';cmd=['cc','-std=c11','-Wall','-Wextra','-Werror','-I',str(inc.parent),str(source),'-o',str(oracle)]
  if chip=='esp32c6':cmd.insert(1,'-DC6')
  subprocess.run(cmd,check=True);expected=w/'expected.bin';expected.write_bytes(subprocess.check_output([str(oracle)]))
  # Test controller addresses from production compiler helpers as well.
  compiler_source=(root/'compiler/main.flex').read_text().replace('fn main(argc, argv)','fn irq_oracle_compiler_main(argc, argv)').replace('fn main(argc,argv)','fn irq_oracle_compiler_main(argc,argv)')
  compiler_source=re.sub(r'^import "([^\"]+)";',lambda m:'import "'+str((root/'compiler'/m[1]).resolve())+'";',compiler_source,flags=re.M)
  imported=w/'compiler.flex';imported.write_text(compiler_source);header=struct.unpack_from('<14Q',expected.read_bytes());probe=w/'selectors.flex';probe.write_text('import "'+str(imported)+'";fn main(){rv_target='+('2' if chip=='esp32c6' else '1')+';return rv_irq_enable_reg()!='+str(header[10])+' || rv_irq_pending_reg()!='+str(header[11])+' || rv_irq_soft_reg()!='+str(header[12])+';}');selectors=w/'selectors';subprocess.run([a.compiler,str(probe),'-o',str(selectors)],check=True);subprocess.run([str(selectors)],check=True)
  source=w/'model.flex';source.write_text(f'import "{root}/scripts/lib/build.flex";\nimport "{root}/lib/platform/{chip}-irq.flex";\nimport "{root}/lib/platform/{chip}-timer.flex";\n'+F);binary=w/'model';subprocess.run([a.compiler,str(source),'-o',str(binary)],check=True);checks,writes=struct.unpack('<QQ',subprocess.check_output([str(binary),str(expected)]));cases.append(dict(chip=chip,checks=checks+3,exact_writes=writes,CPU_execution=False,physical_hardware=False));print(chip,checks+3,'IRQ/timer header checks,',writes,'exact writes')
 (a.work/'report.json').write_text(json.dumps(dict(pass_all=True,cases=cases,reference='ESP-IDF v5.5.1 primary headers',physical_hardware=False),indent=2)+'\n')
if __name__=='__main__':main()
