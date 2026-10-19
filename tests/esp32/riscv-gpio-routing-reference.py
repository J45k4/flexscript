#!/usr/bin/env python3
"""C primary-header oracle against production C3/C6 GPIO routing and IRQ writes.

The native adapter harness verifies MMIO policy. It is not chip execution or a
pin-edge emulator. Stock Espressif QEMU has a stub GPIO device.
"""
import argparse,hashlib,json,shutil,struct,subprocess
from pathlib import Path
C=r'''
#include <stdint.h>
#include <stdio.h>
#include "soc/interrupts.h"
#include "soc/gpio_reg.h"
#include "soc/io_mux_reg.h"
#include "soc/gpio_sig_map.h"
static uint64_t trace[8192][3];static unsigned count;
static uint32_t get(uint32_t a){for(unsigned i=count;i;i--)if(trace[i-1][0]==a)return trace[i-1][1];return 0xa5a5a5a5;}
static void put(uint32_t a,uint32_t v,unsigned masked){trace[count][0]=a;trace[count][1]=v;trace[count++][2]=masked;}
static void update(uint32_t a,uint32_t m,uint32_t v){put(a,(get(a)&~m)|(v&m),1);}
static void mux(unsigned p){uint32_t a=IO_MUX_GPIO0_REG+p*4;put(a,(get(a)&~MCU_SEL_M)|(FUNC_MTMS_GPIO4<<MCU_SEL_S)|FUN_IE,1);}
int main(void){
#ifdef C6
 uint64_t header[]={0x40830000,30,24,30,ETS_GPIO_INTR_SOURCE,0};
#else
 uint64_t header[]={0x3fca0000,21,11,17,ETS_GPIO_INTR_SOURCE,0};
#endif
 for(unsigned pin=0;pin<=header[1];pin++){
  if(pin>=header[2]&&pin<=header[3])continue;
  for(unsigned signal=0;signal<=SIG_GPIO_OUT_IDX;signal++){
   mux(pin);put(GPIO_FUNC0_OUT_SEL_CFG_REG+pin*4,SIG_GPIO_OUT_IDX|GPIO_FUNC0_OEN_SEL,1);put(GPIO_ENABLE_W1TS_REG,1u<<pin,1);
   put(GPIO_FUNC0_OUT_SEL_CFG_REG+pin*4,signal|GPIO_FUNC0_OEN_SEL,1);
   if(signal<SIG_GPIO_OUT_IDX){mux(pin);put(GPIO_FUNC0_IN_SEL_CFG_REG+signal*4,pin|GPIO_SIG0_IN_SEL,1);}
  }
  for(unsigned mode=0;mode<=5;mode++){
   uint32_t a=GPIO_PIN0_REG+pin*4;
   update(a,GPIO_PIN0_INT_ENA_M,0);update(a,GPIO_PIN0_INT_TYPE_M,mode<<GPIO_PIN0_INT_TYPE_S);
   put(GPIO_STATUS_W1TC_REG,1u<<pin,1);
   if(mode)update(a,GPIO_PIN0_INT_ENA_M,1u<<GPIO_PIN0_INT_ENA_S);
   put(GPIO_STATUS_W1TC_REG,1u<<pin,0);
  }
 }
 header[5]=count;fwrite(header,sizeof header,1,stdout);fwrite(trace,sizeof trace[0],count,stdout);return ferror(stdout)?1:0;
}
'''
# Trace capacity covers all valid pads times all128 peripheral signals.
C=C.replace('trace[8192]','trace[32768]')
F=r'''
global expected=0;global regs=0;global writes=0;global checks=0;global model_ps=0x1888;global foreign=0;
fn check(ok){checks=checks+1;if !ok{h_print(2,h_cat3("GPIO route check ",h_int(checks)," failed\n"));syscall(60,1,0,0,0,0,0);}return 0;}
fn esp32_state(){if foreign{return 17;}return load64(expected);}
fn esp32_cycles(){return 0;}
fn esp32_irq_save(){let old=model_ps;model_ps=model_ps&~8;return old;}
fn esp32_irq_restore(value){model_ps=value;return 0;}
fn esp32_load32(address){if address==rv_hal_gpio+0x44{return 0xa5a5a5a5;}let i=writes;while i{i=i-1;if load64(regs+i*16)==address{return load64(regs+i*16+8);}}return 0xa5a5a5a5;}
fn esp32_store32(address,value){check(writes<load64(expected+40));let row=expected+48+writes*24;check(address==load64(row));check((value&4294967295)==load64(row+8));if load64(row+16){check(!(model_ps&8));}store64(regs+writes*16,address);store64(regs+writes*16+8,value&4294967295);writes=writes+1;return 0;}
fn main(argc,argv){h_environment(argc,argv);expected=h_read(load64(argv+8));regs=alloc(1048576);check(esp_gpio_irq_source()==load64(expected+32));
 let pin=0;while pin<=load64(expected+8){
  if pin<load64(expected+16)||pin>load64(expected+24){
   let signal=0;while signal<=128 {check(!esp_gpio_route_output(pin,signal));if signal<128{check(!esp_gpio_route_input(pin,signal));}check(model_ps==0x1888);signal=signal+1;}
   let mode=0;while mode<=5{check(!esp_gpio_irq(pin,mode));check(model_ps==0x1888);check(esp_gpio_irq_pending(pin)==((0xa5a5a5a5>>pin)&1));check(!esp_gpio_irq_ack(pin));mode=mode+1;}
  }else{let before=writes;check(esp_gpio_route_output(pin,0)==-22&&esp_gpio_route_input(pin,0)==-22&&esp_gpio_irq(pin,1)==-22&&esp_gpio_irq_pending(pin)==-22&&esp_gpio_irq_ack(pin)==-22&&writes==before);}pin=pin+1;
 }
 let before=writes;check(esp_gpio_route_output(-1,0)==-22&&esp_gpio_route_output(4,-1)==-22&&esp_gpio_route_output(4,129)==-22&&esp_gpio_route_output(1<<32,0)==-22);check(esp_gpio_route_input(4,128)==-22&&esp_gpio_route_input(4,-1)==-22&&esp_gpio_route_input(load64(expected+8)+1,0)==-22);check(esp_gpio_irq(4,-1)==-22&&esp_gpio_irq(4,6)==-22&&esp_gpio_irq(1<<32,1)==-22&&esp_gpio_irq_pending(-1)==-22&&esp_gpio_irq_ack(1<<32)==-22);
 foreign=1;check(esp_gpio_irq_source()==-95&&esp_gpio_route_output(4,0)==-22&&esp_gpio_irq(4,1)==-22);foreign=0;check(writes==before&&writes==load64(expected+40)&&model_ps==0x1888);
 let out=alloc(16);store64(out,checks);store64(out+8,writes);return syscall(1,1,out,16,0,0,0)!=16;}
'''
def main():
 p=argparse.ArgumentParser();p.add_argument('--compiler',required=True);p.add_argument('--reference',type=Path,required=True);p.add_argument('--work',type=Path,required=True);a=p.parse_args();root=Path(__file__).resolve().parents[2];a.work.mkdir(parents=True,exist_ok=True);cases=[]
 for chip in ('esp32c3','esp32c6'):
  w=a.work/chip;inc=w/'include/soc';inc.mkdir(parents=True,exist_ok=True)
  for folder in ('register/soc','include/soc'):
   for f in (a.reference/'components/soc'/chip/folder).glob('*.h'):shutil.copyfile(f,inc/f.name)
  (inc.parent/'esp_assert.h').write_text('#pragma once\n');(inc.parent/'esp_bit_defs.h').write_text('#pragma once\n#define BIT(n) (1U<<(n))\n#define BIT64(n) (1ULL<<(n))\n')
  source=w/'oracle.c';source.write_text(C);oracle=w/'oracle';cmd=['cc','-std=c11','-Wall','-Wextra','-Werror','-I',str(inc.parent),str(source),'-o',str(oracle)]
  if chip=='esp32c6':cmd.insert(1,'-DC6')
  subprocess.run(cmd,check=True);expected=w/'expected.bin';expected.write_bytes(subprocess.check_output([str(oracle)]))
  source=w/'model.flex';source.write_text(f'import "{root}/scripts/lib/build.flex";\nimport "{root}/lib/platform/{chip}-gpio.flex";\n'+F);binary=w/'model';subprocess.run([a.compiler,str(source),'-o',str(binary)],check=True);checks,writes=struct.unpack('<QQ',subprocess.check_output([str(binary),str(expected)],timeout=60));cases.append(dict(chip=chip,checks=checks,exact_writes=writes,CPU_execution=False,physical_hardware=False));print(chip,checks,'GPIO matrix/IRQ header checks,',writes,'exact writes')
 (a.work/'report.json').write_text(json.dumps(dict(pass_all=True,cases=cases,reference='ESP-IDF v5.5.1 unmodified primary headers',physical_hardware=False),indent=2)+'\n')
if __name__=='__main__':main()
