#!/usr/bin/env python3
"""Pinned C-header oracle for ROM-configured UART0 FIFO/IRQ adapters."""
import argparse,json,shutil,struct,subprocess
from pathlib import Path
C=r'''
#include <stdint.h>
#include <stdio.h>
#include "soc/uart_reg.h"
#include "soc/interrupts.h"
static uint64_t trace[256][3];static unsigned count;static unsigned auto_sync;
static uint32_t get(uint32_t a){uint32_t value=0xa5a5a5a5;for(unsigned i=count;i;i--)if(trace[i-1][0]==a){value=trace[i-1][1];break;}
#ifndef C6
 if(a==UART_ID_REG(0)){value&=~UART_UPDATE;if(auto_sync)value|=UART_HIGH_SPEED;}
#endif
 return value;}
static void put(uint32_t a,uint32_t v,unsigned masked){trace[count][0]=a;trace[count][1]=v;trace[count++][2]=masked;}
static void update(uint32_t a,uint32_t m,uint32_t v){put(a,(get(a)&~m)|(v&m),1);}
static void sync_uart(void){
#ifdef C6
 put(UART_REG_UPDATE_REG(0),UART_REG_UPDATE,1);
#else
 if(!(get(UART_ID_REG(0))&UART_HIGH_SPEED))update(UART_ID_REG(0),UART_UPDATE,UART_UPDATE);
#endif
}
static void thresholds(unsigned rx,unsigned tx){update(UART_CONF1_REG(0),UART_RXFIFO_FULL_THRHD_M|UART_TXFIFO_EMPTY_THRHD_M,(rx<<UART_RXFIFO_FULL_THRHD_S)|(tx<<UART_TXFIFO_EMPTY_THRHD_S));sync_uart();}
int main(void){
#ifdef C6
 uint64_t header[]={0x40830000,ETS_UART0_INTR_SOURCE,UART_RXFIFO_CNT_V,0,0};
#else
 uint64_t header[]={0x3fca0000,ETS_UART0_INTR_SOURCE,UART_RXFIFO_CNT_V,0,0};
#endif
 unsigned rx[]={1,2,64,127},tx[]={0,1,127};for(unsigned r=0;r<4;r++)for(unsigned t=0;t<3;t++)thresholds(rx[r],tx[t]);
 unsigned timeout[]={0,1,2,1023};for(unsigned i=0;i<4;i++){
#ifdef C6
  update(UART_TOUT_CONF_SYNC_REG(0),UART_RX_TOUT_EN|UART_RX_TOUT_THRHD_M,timeout[i]?UART_RX_TOUT_EN|(timeout[i]<<UART_RX_TOUT_THRHD_S):0);
#else
  if(timeout[i])update(UART_MEM_CONF_REG(0),UART_RX_TOUT_THRHD_M,timeout[i]<<UART_RX_TOUT_THRHD_S);
  update(UART_CONF1_REG(0),UART_RX_TOUT_EN,timeout[i]?UART_RX_TOUT_EN:0);
#endif
  sync_uart();
 }
 unsigned mask[]={0,1,UART_TX_DONE_INT_ENA,0x7ffff};for(unsigned i=0;i<4;i++){put(UART_INT_ENA_REG(0),mask[i],0);put(UART_INT_CLR_REG(0),mask[i],0);}
 put(UART_FIFO_REG(0),255,1);auto_sync=1;thresholds(8,10);auto_sync=0;thresholds(7,9);header[3]=count;fwrite(header,sizeof header,1,stdout);fwrite(trace,sizeof trace[0],count,stdout);return ferror(stdout)?1:0;
}
'''
F=r'''
global expected=0;global regs=0;global writes=0;global checks=0;global model_ps=0x1888;global foreign=0;global status=0;global stuck=0;global cycle=0;global auto_sync=0;
fn check(ok){checks=checks+1;if !ok{h_print(2,h_cat3("UART oracle check ",h_int(checks)," failed\n"));syscall(60,1,0,0,0,0,0);}return 0;}
fn esp32_state(){if foreign{return 17;}return load64(expected);}
fn esp32_cycles(){cycle=cycle+500000;return cycle;}
fn esp32_irq_save(){let old=model_ps;model_ps=model_ps&~8;return old;}
fn esp32_irq_restore(value){model_ps=value;return 0;}
fn esp32_load32(address){if address==0x6000001c{return status;}if address==0x60000000{return 165;}if address==0x60000098 {return stuck;}let i=writes;let result=0xa5a5a5a5;let found=0;while i&&!found {i=i-1;if load64(regs+i*16)==address{result=load64(regs+i*16+8);found=1;}}if address==0x60000080 {result=result&0x7fffffff;if stuck {result=result|(1<<31);}if auto_sync {result=result|(1<<30);}}return result;}
fn esp32_store32(address,value){check(writes<load64(expected+24));let row=expected+40+writes*24;check(address==load64(row));check((value&4294967295)==load64(row+8));if load64(row+16){check(!(model_ps&8));}store64(regs+writes*16,address);store64(regs+writes*16+8,value&4294967295);writes=writes+1;return 0;}
fn main(argc,argv){h_environment(argc,argv);expected=h_read(load64(argv+8));regs=alloc(65536);check(esp_uart_irq_source()==load64(expected+8));check(rv_hal_uart_mask==load64(expected+16));
 let r=0;while r<4 {let rx=1;if r==1 {rx=2;}else if r==2 {rx=64;}else if r==3 {rx=127;}let t=0;while t<3 {let tx=0;if t==1 {tx=1;}else if t==2 {tx=127;}check(!esp_uart_irq_thresholds(rx,tx));check(model_ps==0x1888);t=t+1;}r=r+1;}
 let i=0;while i<4 {let bits=0;if i==1 {bits=1;}else if i==2 {bits=2;}else if i==3 {bits=1023;}check(!esp_uart_irq_timeout(bits));check(model_ps==0x1888);i=i+1;}
 i=0;while i<4 {let mask=0;if i==1 {mask=1;}else if i==2 {mask=1<<14;}else if i==3 {mask=0x7ffff;}check(!esp_uart_irq_mask(mask)&&!esp_uart_irq_ack(mask));i=i+1;}
 check(esp_uart_irq_pending()==(0xa5a5a5a5&0x7ffff)&&esp_uart_irq_raw()==(0xa5a5a5a5&0x7ffff));check(esp_uart_try_read()==-1);status=1;check(esp_uart_try_read()==165);status=0;check(!esp_uart_try_putc(255));status=128<<16;check(esp_uart_try_putc(17)==-11&&model_ps==0x1888);status=0;
 let before=writes;check(esp_uart_irq_thresholds(0,0)==-22&&esp_uart_irq_thresholds(128,0)==-22&&esp_uart_irq_thresholds(1,128)==-22&&esp_uart_irq_thresholds(1,-1)==-22);check(esp_uart_irq_timeout(-1)==-22&&esp_uart_irq_timeout(1024)==-22&&esp_uart_irq_timeout(1<<32)==-22);check(esp_uart_irq_mask(-1)==-22&&esp_uart_irq_mask(1<<19)==-22&&esp_uart_irq_mask(1<<32)==-22&&esp_uart_irq_ack(-1)==-22&&esp_uart_irq_ack(1<<32)==-22);check(esp_uart_try_putc(-1)==-22&&esp_uart_try_putc(256)==-22&&esp_uart_try_putc(1<<32)==-22);
 foreign=1;check(esp_uart_irq_source()==-95&&esp_uart_irq_mask(0)==-95&&esp_uart_irq_ack(0)==-95&&esp_uart_irq_pending()==-95&&esp_uart_irq_raw()==-95&&esp_uart_try_read()==-95&&esp_uart_try_putc(0)==-95&&esp_uart_update()==-95&&esp_uart_irq_thresholds(1,0)==-95&&esp_uart_irq_timeout(0)==-95);foreign=0;check(writes==before);
 auto_sync=1;check(!esp_uart_irq_thresholds(8,10)&&model_ps==0x1888);auto_sync=0;stuck=1;check(esp_uart_irq_thresholds(7,9)==-110&&model_ps==0x1888);check(writes==load64(expected+24));let out=alloc(16);store64(out,checks);store64(out+8,writes);return syscall(1,1,out,16,0,0,0)!=16;}
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
  source=w/'model.flex';source.write_text(f'import "{root}/scripts/lib/build.flex";\nimport "{root}/lib/platform/{chip}-uart.flex";\n'+F);binary=w/'model';subprocess.run([a.compiler,str(source),'-o',str(binary)],check=True);checks,writes=struct.unpack('<QQ',subprocess.check_output([str(binary),str(expected)]));cases.append(dict(chip=chip,checks=checks,exact_writes=writes,CPU_execution=False,physical_hardware=False));print(chip,checks,'UART FIFO/IRQ header checks,',writes,'exact writes')
 (a.work/'report.json').write_text(json.dumps(dict(pass_all=True,cases=cases,reference='ESP-IDF v5.5.1 primary headers',physical_hardware=False),indent=2)+'\n')
if __name__=='__main__':main()
