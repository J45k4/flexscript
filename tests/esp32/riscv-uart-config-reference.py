#!/usr/bin/env python3
"""C primary-header oracle for two-port UART initialization and configuration.

Native MMIO instrumentation checks policy; it does not supply missing stock
QEMU clock models or claim physical baud, flow-control or pad acceptance.
"""
import argparse,json,shutil,struct,subprocess
from pathlib import Path
C=r'''
#include <stdint.h>
#include <stdio.h>
#include "soc/uart_reg.h"
#include "soc/gpio_reg.h"
#include "soc/io_mux_reg.h"
#include "soc/gpio_sig_map.h"
#include "soc/interrupts.h"
#ifdef C6
#include "soc/pcr_reg.h"
#define CONF0(b) UART_CONF0_SYNC_REG(b)
#define DIVREG(b) UART_CLKDIV_SYNC_REG(b)
#else
#include "soc/system_reg.h"
#define CONF0(b) UART_CONF0_REG(b)
#define DIVREG(b) UART_CLKDIV_REG(b)
#endif
static uint64_t trace[16384][2];static unsigned count;
static uint32_t get(uint32_t a){uint32_t value=0xa5a5a5a5;for(unsigned i=count;i;i--)if(trace[i-1][0]==a){value=trace[i-1][1];goto ready;}
#ifdef C6
 if(a==PCR_UART0_CONF_REG||a==PCR_UART1_CONF_REG)value&=~3u;
#endif
 for(unsigned b=0;b<2;b++){
  if(a==UART_STATUS_REG(b)||a==UART_INT_ENA_REG(b)||a==UART_FSM_STATUS_REG(b))return 0;
#ifndef C6
  if(a==UART_CLK_CONF_REG(b))value&=~(UART_RST_CORE|UART_RX_RST_CORE|UART_TX_RST_CORE);
#endif
 }
#ifndef C6
 if(a==SYSTEM_PERIP_CLK_EN0_REG)value=0xcafe0000;
 if(a==SYSTEM_PERIP_RST_EN0_REG)value=0xbabe0000;
#endif
ready:
#ifndef C6
 for(unsigned b=0;b<2;b++)if(a==UART_ID_REG(b))value&=~UART_UPDATE;
#endif
 return value;}
static void put(uint32_t a,uint32_t v){trace[count][0]=a;trace[count++][1]=v;}
static void update(uint32_t a,uint32_t m,uint32_t v){put(a,(get(a)&~m)|(v&m));}
static void sync_uart(unsigned b){
#ifdef C6
 put(UART_REG_UPDATE_REG(b),UART_REG_UPDATE);
#else
 update(UART_ID_REG(b),UART_UPDATE,UART_UPDATE);
#endif
}
static void init(unsigned b,unsigned baud,unsigned bits,unsigned parity,unsigned stop){
 unsigned pre=(40000000ULL+(uint64_t)UART_CLKDIV_V*baud-1)/((uint64_t)UART_CLKDIV_V*baud);unsigned div=640000000ULL/((uint64_t)baud*pre);
#ifdef C6
 uint32_t ctrl=PCR_UART0_CONF_REG+b*(PCR_UART1_CONF_REG-PCR_UART0_CONF_REG),clk=PCR_UART0_SCLK_CONF_REG+b*(PCR_UART1_SCLK_CONF_REG-PCR_UART0_SCLK_CONF_REG);
 if(!(get(ctrl)&PCR_UART0_CLK_EN)){update(ctrl,PCR_UART0_CLK_EN|PCR_UART0_RST_EN,PCR_UART0_CLK_EN|PCR_UART0_RST_EN);update(ctrl,PCR_UART0_RST_EN,0);}
 update(clk,PCR_UART0_SCLK_DIV_A_M|PCR_UART0_SCLK_DIV_B_M|PCR_UART0_SCLK_DIV_NUM_M|PCR_UART0_SCLK_SEL_M|PCR_UART0_SCLK_EN,(3<<PCR_UART0_SCLK_SEL_S)|PCR_UART0_SCLK_EN|((pre-1)<<PCR_UART0_SCLK_DIV_NUM_S));
#else
 uint32_t bit=b?SYSTEM_UART1_CLK_EN:SYSTEM_UART_CLK_EN,clk=UART_CLK_CONF_REG(b);
 if(!(get(SYSTEM_PERIP_CLK_EN0_REG)&bit)){update(SYSTEM_PERIP_RST_EN0_REG,bit,0);update(clk,UART_RST_CORE,UART_RST_CORE);update(SYSTEM_PERIP_CLK_EN0_REG,bit,bit);update(SYSTEM_PERIP_RST_EN0_REG,bit,bit);update(SYSTEM_PERIP_RST_EN0_REG,bit,0);update(clk,UART_RST_CORE,0);}
 update(UART_ID_REG(b),UART_HIGH_SPEED,0);
 update(clk,UART_SCLK_DIV_A_M|UART_SCLK_DIV_B_M|UART_SCLK_DIV_NUM_M|UART_SCLK_SEL_M|UART_SCLK_EN|UART_RX_SCLK_EN|UART_TX_SCLK_EN,(3<<UART_SCLK_SEL_S)|UART_SCLK_EN|UART_RX_SCLK_EN|UART_TX_SCLK_EN|((pre-1)<<UART_SCLK_DIV_NUM_S));
#endif
 update(DIVREG(b),UART_CLKDIV_M|UART_CLKDIV_FRAG_M,((div>>4)<<UART_CLKDIV_S)|((div&15)<<UART_CLKDIV_FRAG_S));
 uint32_t format=((bits-5)<<UART_BIT_NUM_S)|(stop<<UART_STOP_BIT_NUM_S);if(parity)format|=UART_PARITY_EN|(parity==2?UART_PARITY:0);
 update(CONF0(b),UART_PARITY|UART_PARITY_EN|UART_BIT_NUM_M|UART_STOP_BIT_NUM_M|UART_TX_FLOW_EN,format);
#ifdef C6
 update(UART_HWFC_CONF_SYNC_REG(b),UART_RX_FLOW_EN,0);
#else
 update(UART_CONF1_REG(b),UART_RX_FLOW_EN,0);
#endif
 put(UART_INT_CLR_REG(b),0x7ffff);sync_uart(b);
}
static void flow(unsigned b,unsigned mode,unsigned threshold){
#ifdef C6
 update(UART_HWFC_CONF_SYNC_REG(b),UART_RX_FLOW_THRHD_M|UART_RX_FLOW_EN,(mode&1)?threshold|UART_RX_FLOW_EN:0);
#else
 if(mode&1)update(UART_MEM_CONF_REG(b),UART_RX_FLOW_THRHD_M,threshold<<UART_RX_FLOW_THRHD_S);
 update(UART_CONF1_REG(b),UART_RX_FLOW_EN,(mode&1)?UART_RX_FLOW_EN:0);
#endif
 update(CONF0(b),UART_TX_FLOW_EN,(mode&2)?UART_TX_FLOW_EN:0);sync_uart(b);
}
static void mux(unsigned pin){uint32_t a=IO_MUX_GPIO0_REG+pin*4;put(a,(get(a)&~MCU_SEL_M)|(FUNC_MTMS_GPIO4<<MCU_SEL_S)|FUN_IE);}
static void output(unsigned pin,unsigned signal){
 put(GPIO_OUT_W1TS_REG,1u<<pin);update(GPIO_PIN0_REG+pin*4,GPIO_PIN0_PAD_DRIVER,0);mux(pin);put(GPIO_FUNC0_OUT_SEL_CFG_REG+pin*4,SIG_GPIO_OUT_IDX|GPIO_FUNC0_OEN_SEL);put(GPIO_ENABLE_W1TS_REG,1u<<pin);put(GPIO_FUNC0_OUT_SEL_CFG_REG+pin*4,signal|GPIO_FUNC0_OEN_SEL);
}
static void input(unsigned pin,unsigned signal){mux(pin);put(GPIO_ENABLE_W1TC_REG,1u<<pin);update(IO_MUX_GPIO0_REG+pin*4,FUN_PU|FUN_PD,FUN_PU);mux(pin);put(GPIO_FUNC0_IN_SEL_CFG_REG+signal*4,pin|GPIO_SIG0_IN_SEL);}
int main(void){
#ifdef C6
 uint64_t header[16]={0x40830000,0,ETS_UART0_INTR_SOURCE,ETS_UART1_INTR_SOURCE};
#else
 uint64_t header[16]={0x3fca0000,0,ETS_UART0_INTR_SOURCE,ETS_UART1_INTR_SOURCE};
#endif
 header[12]=REG_UART_BASE(0);header[13]=REG_UART_BASE(1);unsigned rates[]={39,40,50,300,9600,115200,1000000,5000000};
 for(unsigned r=0;r<8;r++){unsigned pre=(40000000ULL+(uint64_t)UART_CLKDIV_V*rates[r]-1)/((uint64_t)UART_CLKDIV_V*rates[r]);unsigned div=640000000ULL/((uint64_t)rates[r]*pre);header[4+r]=640000000ULL/((uint64_t)div*pre);}
 for(unsigned b=0;b<2;b++){
  for(unsigned r=0;r<8;r++)for(unsigned bits=5;bits<=8;bits++)for(unsigned parity=0;parity<3;parity++)for(unsigned stop=1;stop<=3;stop++)init(b,rates[r],bits,parity,stop);
  for(unsigned mode=0;mode<4;mode++)flow(b,mode,mode?64:0);
  output(4,b?U1TXD_OUT_IDX:U0TXD_OUT_IDX);input(5,b?U1RXD_IN_IDX:U0RXD_IN_IDX);output(6,b?U1RTS_OUT_IDX:U0RTS_OUT_IDX);input(7,b?U1CTS_IN_IDX:U0CTS_IN_IDX);
  put(UART_INT_ENA_REG(b),1);put(UART_INT_CLR_REG(b),1);put(UART_INT_ENA_REG(b),0);
 }
 // Last initialization's sync bit stays busy in the fault-injection harness.
 init(1,115200,8,0,1);header[1]=count;fwrite(header,sizeof header,1,stdout);fwrite(trace,sizeof trace[0],count,stdout);return ferror(stdout)?1:0;
}
'''
F=r'''
global expected=0;global regs=0;global writes=0;global checks=0;global model_ps=0x1888;global foreign=0;global stuck=0;global stuck_requested=0;global cycle=0;global busy_mode=0;global busy_bus=0;global baud_fault=0;
fn check(ok){checks=checks+1;if !ok{h_print(2,h_cat3("UART config check ",h_int(checks)," failed\n"));h_print(2,h_cat3("writes=",h_int(writes),h_cat3(" busy=",h_int(busy_mode),"\n")));syscall(60,1,0,0,0,0,0);}return 0;}
fn esp32_state(){if foreign{return 17;}return load64(expected);}
fn esp32_cycles(){cycle=cycle+500000;return cycle;}
fn esp32_irq_save(){let old=model_ps;model_ps=model_ps&~8;return old;}
fn esp32_irq_restore(value){model_ps=value;return 0;}
fn esp32_load32(address){
 if address==esp32_state()+16 {return busy_mode==6;}
 let value=0xa5a5a5a5;let found=0;let i=writes;while i&&!found {i=i-1;if load64(regs+i*16)==address{value=load64(regs+i*16+8);found=1;}}
 let b=0;while b<2 {let base=load64(expected+96+b*8);
  if address==base+0x98 {if busy_mode==9&&b==busy_bus {return 1;}return stuck;}if address==base+0x80 {value=value&0x7fffffff;if stuck||(busy_mode==9&&b==busy_bus){value=value|(1<<31);}}
  if !found {if address==base+0x1c||address==base+12 {value=0;}let fsm=base+0x6c;if rv_hal_state==0x40830000 {fsm=base+0x70;}if address==fsm{value=0;}if rv_hal_state==0x3fca0000&&address==base+0x78{value=value&~((1<<23)|(3<<26));}}
  b=b+1;
 }
 if !found&&rv_hal_state==0x40830000&&(address==0x60096000||address==0x6009600c){value=value&~3;}if !found&&address==0x600c0010 {value=0xcafe0000;}if !found&&address==0x600c0018 {value=0xbabe0000;}
 let base=load64(expected+96+busy_bus*8);let fsm=base+0x6c;if rv_hal_state==0x40830000 {fsm=base+0x70;}
 if busy_mode==1&&address==base+12 {value=1;}if busy_mode==2&&address==base+0x1c {value=1;}if busy_mode==3&&address==base+0x1c {value=1<<16;}if busy_mode==4&&address==fsm {value=1;}if busy_mode==5&&address==fsm {value=16;}
 if busy_mode==7 {if rv_hal_state==0x40830000&&address==0x60096000+busy_bus*12 {value=value|2;}else if rv_hal_state==0x3fca0000&&address==0x600c0018 {value=value|(1<<(2+busy_bus*3));}}
 if busy_mode==8&&rv_hal_state==0x3fca0000&&address==base+0x78 {value=value|(1<<23);}let clock=base+0x78;if rv_hal_state==0x40830000 {clock=0x60096004+busy_bus*12;}if address==clock {if baud_fault==1 {value=(value&~(3<<20))|(1<<20);}else if baud_fault==2 {value=value|1;}}if baud_fault==3&&address==base+0x14 {value=0;}return value;
}
fn esp32_store32(address,value){if stuck_requested&&((rv_hal_state==0x3fca0000&&address==load64(expected+104)+0x80&&(value&(1<<31)))||(rv_hal_state==0x40830000&&address==load64(expected+104)+0x98)){stuck=1;}check(writes<load64(expected+8));let row=expected+128+writes*16;check(address==load64(row));check((value&4294967295)==load64(row+8));check(!(model_ps&8)||address==0x6000000c||address==0x60000010||address==load64(expected+104)+12||address==load64(expected+104)+16);store64(regs+writes*16,address);store64(regs+writes*16+8,value&4294967295);writes=writes+1;return 0;}
fn rate(n){if n==0{return 39;}if n==1{return 40;}if n==2{return 50;}if n==3{return 300;}if n==4{return 9600;}if n==5{return 115200;}if n==6{return 1000000;}return 5000000;}
fn invalid(bus){let before=writes;check(esp_uart_bus_init(bus,0,8,0,1)==-22&&esp_uart_bus_init(bus,38,8,0,1)==-22&&esp_uart_bus_init(bus,5000001,8,0,1)==-22&&esp_uart_bus_init(bus,1<<32,8,0,1)==-22);check(esp_uart_bus_init(bus,115200,4,0,1)==-22&&esp_uart_bus_init(bus,115200,9,0,1)==-22&&esp_uart_bus_init(bus,115200,8,3,1)==-22&&esp_uart_bus_init(bus,115200,8,-1,1)==-22&&esp_uart_bus_init(bus,115200,8,0,0)==-22&&esp_uart_bus_init(bus,115200,8,0,4)==-22);check(esp_uart_bus_flow(bus,4,64)==-22&&esp_uart_bus_flow(bus,1,0)==-22&&esp_uart_bus_flow(bus,1,128)==-22&&esp_uart_bus_flow(bus,-1,0)==-22);check(esp_uart_bus_pins(bus,4,4,-1,-1)==-22&&esp_uart_bus_pins(bus,4,5,4,-1)==-22&&esp_uart_bus_pins(bus,4,5,6,6)==-22&&esp_uart_bus_pins(bus,4,5,rv_hal_reserved_start,-1)==-22&&esp_uart_bus_pins(bus,1<<32,5,-1,-1)==-22);check(before==writes&&model_ps==0x1888);return 0;}
fn main(argc,argv){h_environment(argc,argv);expected=h_read(load64(argv+8));regs=alloc(1048576);
 let b=0;while b<2 {check(esp_uart_bus_base(b)==load64(expected+96+b*8));check(!esp_uart_bus_enabled(b));check(esp_uart_bus_baud(b)==-19&&esp_uart_bus_flow(b,0,0)==-19);invalid(b);let r=0;while r<8{let bits=5;while bits<=8{let parity=0;while parity<3{let stop=1;while stop<=3{check(!esp_uart_bus_init(b,rate(r),bits,parity,stop));check(esp_uart_bus_baud(b)==load64(expected+32+r*8));check(model_ps==0x1888&&esp_uart_bus_enabled(b)==1);stop=stop+1;}parity=parity+1;}bits=bits+1;}r=r+1;}
  let mode=0;while mode<4 {let threshold=0;if mode{threshold=64;}check(!esp_uart_bus_flow(b,mode,threshold));check(model_ps==0x1888);mode=mode+1;}
  check(!esp_uart_bus_pins(b,4,5,6,7));check(!esp_uart_bus_pins(b,-1,-1,-1,-1));check(esp_uart_bus_irq_source(b)==load64(expected+16+b*8));check(!esp_uart_bus_irq_mask(b,1)&&!esp_uart_bus_irq_ack(b,1)&&!esp_uart_bus_irq_mask(b,0));invalid(b);
  busy_bus=b;busy_mode=1;while busy_mode<=9 {if rv_hal_state==0x40830000&&busy_mode==8 {busy_mode=9;}let before=writes;check(esp_uart_bus_init(b,115200,8,0,1)==-16);check(esp_uart_bus_flow(b,0,0)==-16);check(esp_uart_bus_pins(b,4,5,6,7)==-16);check(writes==before&&model_ps==0x1888);busy_mode=busy_mode+1;}busy_mode=0;let fault=1;while fault<=3 {baud_fault=fault;check(esp_uart_bus_baud(b)==-95);fault=fault+1;}baud_fault=0;check(!esp_uart_bus_flush(b,0));busy_mode=3;check(esp_uart_bus_flush(b,1000000)==-110&&model_ps==0x1888);busy_mode=5;check(esp_uart_bus_flush(b,1000000)==-110&&model_ps==0x1888);busy_mode=0;check(esp_uart_bus_flush(b,-1)==-22&&esp_uart_bus_flush(b,2147483648)==-22);b=b+1;
 }
 let before=writes;check(esp_uart_bus_base(-1)==-22&&esp_uart_bus_base(2)==-22&&esp_uart_bus_base(1<<32)==-22&&esp_uart_bus_init(2,115200,8,0,1)==-22&&esp_uart_bus_try_read(-1)==-22&&esp_uart_bus_try_putc(2,0)==-22&&esp_uart_bus_irq_mask(2,0)==-22&&esp_uart_bus_irq_ack(2,0)==-22&&esp_uart_bus_update(2)==-22&&esp_uart_bus_irq_timeout(2,0)==-22&&esp_uart_bus_irq_thresholds(2,1,0)==-22);foreign=1;check(esp_uart_bus_base(0)==-95&&esp_uart_bus_init(0,115200,8,0,1)==-95&&esp_uart_bus_flow(0,0,0)==-95&&esp_uart_bus_pins(0,4,5,6,7)==-95);foreign=0;check(writes==before);
 stuck_requested=1;check(esp_uart_bus_init(1,115200,8,0,1)==-110&&model_ps==0x1888);check(writes==load64(expected+8));let out=alloc(16);store64(out,checks);store64(out+8,writes);return syscall(1,1,out,16,0,0,0)!=16;}
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
  source=w/'model.flex';source.write_text(f'import "{root}/scripts/lib/build.flex";\nimport "{root}/lib/platform/{chip}-uart.flex";\n'+F);binary=w/'model';subprocess.run([a.compiler,str(source),'-o',str(binary)],check=True);checks,writes=struct.unpack('<QQ',subprocess.check_output([str(binary),str(expected)],timeout=60));cases.append(dict(chip=chip,checks=checks,exact_writes=writes,baud_rates=8,frame_combinations=36,ports=2,CPU_execution=False,physical_hardware=False));print(chip,checks,'UART0/1 config header checks,',writes,'exact writes')
 (a.work/'report.json').write_text(json.dumps(dict(pass_all=True,cases=cases,reference='ESP-IDF v5.5.1 primary headers and UART LL',physical_hardware=False),indent=2)+'\n')
if __name__=='__main__':main()
