#!/usr/bin/env python3
"""Pinned SPI2/GPIO C headers versus the production RISC-V FIFO driver.

Native instrumentation supplies independent scripted peripheral responses.
It is not a CPU emulator or evidence of physical SPI wire timing.
"""
import argparse,json,shutil,struct,subprocess
from pathlib import Path
C=r'''
#include <stdint.h>
#include <stdio.h>
#include "soc/spi_reg.h"
#include "soc/gpio_reg.h"
#include "soc/io_mux_reg.h"
#include "soc/gpio_sig_map.h"
#ifdef C6
#include "soc/pcr_reg.h"
#else
#include "soc/system_reg.h"
#endif
static uint64_t trace[32768][3];static unsigned count;static uint32_t saved_clock,saved_user,saved_misc;
static uint32_t get(uint32_t a){for(unsigned i=count;i;i--)if(trace[i-1][0]==a)return trace[i-1][1];
#ifndef C6
 if(a==SYSTEM_PERIP_CLK_EN0_REG)return 0xcafe0040;
 if(a==SYSTEM_PERIP_RST_EN0_REG)return 0xbabe0000;
#endif
 return 0xa5a5a5a5;}
static void put(uint32_t a,uint32_t v,unsigned masked){trace[count][0]=a;trace[count][1]=v;trace[count++][2]=masked;}
static void update(uint32_t a,uint32_t m,uint32_t v){put(a,(get(a)&~m)|(v&m),1);}
static void reset(void){
#ifdef C6
 update(PCR_SPI2_CONF_REG,PCR_SPI2_CLK_EN|PCR_SPI2_RST_EN,PCR_SPI2_CLK_EN|PCR_SPI2_RST_EN);update(PCR_SPI2_CONF_REG,PCR_SPI2_RST_EN,0);update(PCR_SPI2_CLKM_CONF_REG,PCR_SPI2_CLKM_SEL_M|PCR_SPI2_CLKM_EN,PCR_SPI2_CLKM_EN);
#else
 update(SYSTEM_PERIP_CLK_EN0_REG,SYSTEM_SPI2_CLK_EN,SYSTEM_SPI2_CLK_EN);update(SYSTEM_PERIP_RST_EN0_REG,SYSTEM_SPI2_RST,SYSTEM_SPI2_RST);update(SYSTEM_PERIP_RST_EN0_REG,SYSTEM_SPI2_RST,0);update(SPI_CLK_GATE_REG(2),SPI_CLK_EN|SPI_MST_CLK_ACTIVE|SPI_MST_CLK_SEL,SPI_CLK_EN|SPI_MST_CLK_ACTIVE);
#endif
 put(SPI_CMD_REG(2),0,1);put(SPI_CTRL_REG(2),0,1);put(SPI_CLOCK_REG(2),saved_clock,1);put(SPI_USER_REG(2),saved_user,1);put(SPI_USER1_REG(2),0,1);put(SPI_USER2_REG(2),0,1);put(SPI_MISC_REG(2),saved_misc,1);put(SPI_DMA_CONF_REG(2),0,1);put(SPI_DMA_INT_ENA_REG(2),0,1);put(SPI_DMA_INT_CLR_REG(2),0x1fffff,1);put(SPI_SLAVE_REG(2),0,1);
}
static void mux(unsigned p){uint32_t a=IO_MUX_GPIO0_REG+p*4;put(a,(get(a)&~MCU_SEL_M)|(FUNC_MTMS_GPIO4<<MCU_SEL_S)|FUN_IE,1);}
static void output(unsigned p,unsigned signal,unsigned level){put(level?GPIO_OUT_W1TS_REG:GPIO_OUT_W1TC_REG,1u<<p,1);mux(p);put(GPIO_FUNC0_OUT_SEL_CFG_REG+p*4,SIG_GPIO_OUT_IDX|GPIO_FUNC0_OEN_SEL,1);put(GPIO_ENABLE_W1TS_REG,1u<<p,1);put(GPIO_FUNC0_OUT_SEL_CFG_REG+p*4,signal|GPIO_FUNC0_OEN_SEL,1);update(GPIO_PIN0_REG+p*4,GPIO_PIN0_PAD_DRIVER,0);}
static void input(unsigned p){mux(p);put(GPIO_ENABLE_W1TC_REG,1u<<p,1);update(IO_MUX_GPIO0_REG+p*4,FUN_PU|FUN_PD,0);}
static void init(unsigned hz,unsigned mode,int tx,int rx){unsigned pre=(40000000ULL+hz*64-1)/(hz*64);unsigned n=(40000000ULL+hz*pre-1)/(hz*pre);if(n<2)n=2;
 saved_clock=((pre-1)<<SPI_CLKDIV_PRE_S)|((n-1)<<SPI_CLKCNT_N_S)|((n/2-1)<<SPI_CLKCNT_H_S)|((n-1)<<SPI_CLKCNT_L_S);saved_user=SPI_DOUTDIN|(((mode&1)^(mode>>1))?SPI_CK_OUT_EDGE:0);saved_misc=SPI_CS0_DIS|SPI_CS1_DIS|SPI_CS2_DIS|SPI_CS3_DIS|SPI_CS4_DIS|SPI_CS5_DIS|((mode>>1)?SPI_CK_IDLE_EDGE:0);reset();output(4,FSPICLK_OUT_IDX,mode>>1);if(tx)output(5,FSPID_OUT_IDX,0);if(rx){input(6);update(GPIO_PIN0_REG+6*4,GPIO_PIN0_PAD_DRIVER,0);mux(6);put(GPIO_FUNC0_IN_SEL_CFG_REG+FSPIQ_IN_IDX*4,6|GPIO_SIG0_IN_SEL,1);}}
static void deinit(int tx,int rx){reset();input(4);if(tx)input(5);if(rx)input(6);
#ifdef C6
 update(PCR_SPI2_CLKM_CONF_REG,PCR_SPI2_CLKM_EN,0);update(PCR_SPI2_CONF_REG,PCR_SPI2_CLK_EN,0);
#else
 update(SPI_CLK_GATE_REG(2),SPI_CLK_EN|SPI_MST_CLK_ACTIVE,0);update(SYSTEM_PERIP_CLK_EN0_REG,SYSTEM_SPI2_CLK_EN,0);
#endif
}
static void transfer(unsigned size,int tx,int rx){for(unsigned at=0;at<size;){unsigned amount=size-at;if(amount>64)amount=64;for(unsigned w=0;w<16;w++){uint32_t value=0;for(unsigned b=0;b<4;b++){unsigned pos=w*4+b;if(tx&&pos<amount)value|=(uint32_t)(((at+pos)*37+11)&255)<<(b*8);}put(SPI_W0_REG(2)+w*4,value,0);}put(SPI_USER_REG(2),saved_user|SPI_USR_MOSI|(rx?SPI_USR_MISO:0),0);put(SPI_MS_DLEN_REG(2),amount*8-1,0);put(SPI_DMA_INT_CLR_REG(2),SPI_TRANS_DONE_INT_CLR,0);put(SPI_CMD_REG(2),SPI_UPDATE,0);put(SPI_CMD_REG(2),SPI_USR,0);put(SPI_DMA_INT_CLR_REG(2),SPI_TRANS_DONE_INT_CLR,0);at+=amount;}}
int main(void){
#ifdef C6
 uint64_t h[16]={0x40830000,DR_REG_SPI2_BASE};
#else
 uint64_t h[16]={0x3fca0000,DR_REG_SPI2_BASE};
#endif
 unsigned rates[]={40000,50000,100000,1000000,13000000,20000000};for(unsigned r=0;r<6;r++){unsigned pre=(40000000ULL+rates[r]*64-1)/(rates[r]*64);unsigned n=(40000000ULL+rates[r]*pre-1)/(rates[r]*pre);if(n<2)n=2;h[4+r]=40000000/(pre*n);for(unsigned mode=0;mode<4;mode++){init(rates[r],mode,1,1);transfer(65,1,1);deinit(1,1);}}
 unsigned sizes[]={1,2,3,4,63,64,65,127,128,129,1024,65536};init(1000000,0,1,1);for(unsigned s=0;s<sizeof sizes/sizeof sizes[0];s++)transfer(sizes[s],1,1);transfer(65,1,1);deinit(1,1);
 init(1000000,0,1,0);transfer(65,1,0);deinit(1,0);init(1000000,0,0,1);transfer(65,0,1);deinit(0,1);
 // Error probes prefill a single chunk, then reset without reading uncommitted RX.
 for(unsigned fault=1;fault<=5;fault++){init(1000000,fault&3,1,1);for(unsigned w=0;w<16;w++){uint32_t v=0;for(unsigned b=0;b<4;b++)v|=(uint32_t)(((w*4+b)*37+11)&255)<<(b*8);put(SPI_W0_REG(2)+w*4,v,0);}put(SPI_USER_REG(2),saved_user|SPI_USR_MOSI|SPI_USR_MISO,0);put(SPI_MS_DLEN_REG(2),511,0);put(SPI_DMA_INT_CLR_REG(2),SPI_TRANS_DONE_INT_CLR,0);put(SPI_CMD_REG(2),SPI_UPDATE,0);if(fault!=1)put(SPI_CMD_REG(2),SPI_USR,0);reset();transfer(3,1,1);deinit(1,1);}
 init(1000000,0,1,1);for(unsigned w=0;w<16;w++){uint32_t v=0;for(unsigned b=0;b<4;b++)v|=(uint32_t)(((w*4+b)*37+11)&255)<<(b*8);put(SPI_W0_REG(2)+w*4,v,0);}reset();deinit(1,1);
 // Successful first chunk, then a stuck command in chunk two leaves its RX intact.
 init(1000000,0,1,1);transfer(64,1,1);for(unsigned w=0;w<16;w++){uint32_t v=0;if(!w)v=(64*37+11)&255;put(SPI_W0_REG(2)+w*4,v,0);}put(SPI_USER_REG(2),saved_user|SPI_USR_MOSI|SPI_USR_MISO,0);put(SPI_MS_DLEN_REG(2),7,0);put(SPI_DMA_INT_CLR_REG(2),SPI_TRANS_DONE_INT_CLR,0);put(SPI_CMD_REG(2),SPI_UPDATE,0);put(SPI_CMD_REG(2),SPI_USR,0);reset();deinit(1,1);
 h[2]=count;h[3]=SPI_TRANS_DONE_INT_RAW;fwrite(h,sizeof h,1,stdout);fwrite(trace,sizeof trace[0],count,stdout);return ferror(stdout)?1:0;
}
'''
F=r'''
global expected=0;global regs=0;global writes=0;global checks=0;global ps=0x1888;global foreign=0;global busy=0;global fault=0;global cycle=0;global launched=0;global updated=0;global chunk=0;global running=0;global size_now=0;global tx_now=0;global cycle_fault=0;global state_once=0;
fn check(ok){checks=checks+1;if !ok{h_print(2,h_cat3("SPI header check ",h_int(checks)," failed\n"));h_print(2,h_cat3("writes=",h_int(writes),h_cat3(" fault=",h_int(fault),"\n")));syscall(60,1,0,0,0,0,0);}return 0;}
fn esp32_state(){if foreign{return 17;}return load64(expected);}
fn esp32_cycles(){if running&&fault {cycle=cycle+100;}else{cycle=cycle+1;}return cycle;}
fn esp32_irq_save(){let old=ps;ps=ps&~8;return old;}
fn esp32_irq_restore(value){ps=value;return 0;}
fn spi_base(){return load64(expected+8);}
fn esp32_load32(address){let base=spi_base();if address==esp32_state()+16{return busy==7;}
 if address==base {if busy==1{return 1<<24;}if busy==2{return 1<<23;}if running {if fault==1&&updated&&!launched{return 1<<23;}if launched&&(fault==2||fault==4||fault==5||(fault==6&&chunk>1)){return 1<<24;}}return 0;}
 if address==base+0x34{return busy==3;}if address==base+0x30&&busy==4{return 1<<27;}if address==base+0xe0&&busy==5{return 1<<26;}
 if address==base+0x3c {if !running{return 0;}if fault==5&&launched{return 1<<18;}if fault==3||fault==2{return 0;}if fault==6&&chunk>1{return 0;}if launched{return load64(expected+24);}return 0;}
 if running&&launched&&address>=base+152&&address<base+216 {let offset=(address-base-152)/4*4;let value=0;let i=0;while i<4 {let at=(chunk-1)*64+offset+i;let byte=((at*37+11)&255)^165;if !tx_now{byte=165;}value=value|(byte<<(i*8));i=i+1;}return value;}
 let i=writes;let value=0xa5a5a5a5;let found=0;while i&&!found {i=i-1;if load64(regs+i*16)==address{value=load64(regs+i*16+8);found=1;}}
 if !found {if address==base+0x34||address==base+0x30||address==base+0xe0{value=0;}if address==0x600c0010{value=0xcafe0040;}if address==0x600c0018{value=0xbabe0000;}if address==0x600960c0{value=0xa5a5a5a5;}}
 if busy==6 {if address==0x600c0018{value=value|64;}if address==0x600960c0{value=value|2;}}return value;
}
fn esp32_store32(address,value){check(writes<load64(expected+16));let row=expected+128+writes*24;check(address==load64(row));check((value&4294967295)==load64(row+8));if load64(row+16){check(!(ps&8));}store64(regs+writes*16,address);store64(regs+writes*16+8,value&4294967295);writes=writes+1;
 if address==spi_base() {if value==(1<<23){launched=0;updated=1;}if value==(1<<24){launched=1;chunk=chunk+1;}if !value{launched=0;running=0;updated=0;}}return 0;}
fn rate(r){if r==0{return 40000;}if r==1{return 50000;}if r==2{return 100000;}if r==3{return 1000000;}if r==4{return 13000000;}return 20000000;}
fn fill(tx,rx,size){let i=0;while i<size+16{store8(tx+i,(i*37+11)&255);store8(rx+i,90);i=i+1;}return 0;}
fn verify_rx(rx,size,tx){let i=0;while i<size{let want=((i*37+11)&255)^165;if !tx{want=165;}check(load8(rx+i)==want);i=i+1;}while i<size+16{check(load8(rx+i)==90);i=i+1;}return 0;}
fn transfer(tx,rx,size,with_tx,with_rx){fill(tx,rx,size);running=1;launched=0;updated=0;chunk=0;tx_now=with_tx;let from=0;let to=0;if with_tx{from=tx;}if with_rx{to=rx;}let result=esp_spi_transfer(2,from,to,size,1000000);running=0;check(result==size&&esp_spi_transferred(2)==size&&!esp_spi_status(2)&&ps==0x1888);if with_rx{verify_rx(rx,size,with_tx);}return 0;}
fn guards(tx,rx){let before=writes;check(esp_spi_init(0,4,5,6,1000000,0)==-22&&esp_spi_init(1,4,5,6,1000000,0)==-22&&esp_spi_init(3,4,5,6,1000000,0)==-22);check(esp_spi_init(2,4,4,6,1000000,0)==-22&&esp_spi_init(2,4,-1,-1,1000000,0)==-22&&esp_spi_init(2,4,5,rv_hal_reserved_start,1000000,0)==-22);check(esp_spi_init(2,4,5,6,39999,0)==-22&&esp_spi_init(2,4,5,6,20000001,0)==-22&&esp_spi_init(2,4,5,6,1000000,4)==-22&&esp_spi_init(2,1<<32,5,6,1000000,0)==-22);check(esp_spi_transfer(2,tx,rx,-1,100)==-22&&esp_spi_transfer(2,tx,rx,65537,100)==-22&&esp_spi_transfer(2,tx,rx,1,0)==-22&&esp_spi_transfer(2,0,0,1,100)==-22&&esp_spi_transfer(2,tx,tx+1,65,100)==-22&&esp_spi_transfer(2,1<<32,rx,1,100)==-22&&esp_spi_transfer(2,tx,esp32_state()+180220,8,100)==-22&&esp_spi_transfer(2,esp32_state()+48,rx,8,100)==-22);check(writes==before&&ps==0x1888);return 0;}
fn main(argc,argv){h_environment(argc,argv);expected=h_read(load64(argv+8));regs=alloc(1048576);let arena=esp32_state()+4096;check(syscall(9,arena,176128,3,50,-1,0)==arena);let tx=arena;let rx=arena+69632;check(esp_spi_base(2)==spi_base()&&!esp_spi_base(0)&&!esp_spi_base(1)&&!esp_spi_base(3));guards(tx,rx);check(!esp_spi_transfer(2,0,0,0,100));check(esp_spi_transfer(2,tx,rx,1,100)==-19&&esp_spi_transferred(2)==-19&&esp_spi_status(2)==-19);
 busy=1;while busy<=7 {let before=writes;check(esp_spi_init(2,4,5,6,1000000,0)==-16&&writes==before&&!esp_spi_states);busy=busy+1;}busy=0;
 let r=0;while r<6 {let mode=0;while mode<4 {check(esp_spi_init(2,4,5,6,rate(r),mode)==load64(expected+32+r*8));if !state_once {state_once=esp_spi_states;}check(esp_spi_states==state_once);let before=writes;check(esp_spi_init(2,4,5,6,rate(r),mode)==-16&&writes==before);transfer(tx,rx,65,1,1);check(!esp_spi_deinit(2)&&!esp_spi_deinit(2));mode=mode+1;}r=r+1;}
 check(esp_spi_init(2,4,5,6,1000000,0)==1000000);let sizes=alloc(96);store64(sizes,1);store64(sizes+8,2);store64(sizes+16,3);store64(sizes+24,4);store64(sizes+32,63);store64(sizes+40,64);store64(sizes+48,65);store64(sizes+56,127);store64(sizes+64,128);store64(sizes+72,129);store64(sizes+80,1024);store64(sizes+88,65536);let i=0;while i<12 {transfer(tx,rx,load64(sizes+i*8),1,1);i=i+1;}
 i=0;while i<81{let byte=90;if i<65{byte=(i*37+11)&255;}store8(tx+i,byte);i=i+1;}running=1;launched=0;updated=0;chunk=0;tx_now=1;check(esp_spi_transfer(2,tx,tx,65,1000000)==65);running=0;verify_rx(tx,65,1);
 let before=writes;busy=1;while busy<=7 {check(esp_spi_transfer(2,tx,rx,1,100)==-16&&esp_spi_deinit(2)==-16&&writes==before);busy=busy+1;}busy=0;store64(esp_spi_states+8,1);check(esp_spi_transfer(2,tx,rx,1,100)==-16&&esp_spi_deinit(2)==-16);store64(esp_spi_states+8,0);guards(tx,rx);check(!esp_spi_deinit(2));
 check(esp_spi_init(2,4,5,-1,1000000,0)==1000000);before=writes;check(esp_spi_transfer(2,tx,rx,1,100)==-22&&writes==before);transfer(tx,rx,65,1,0);check(!esp_spi_deinit(2));check(esp_spi_init(2,4,-1,6,1000000,0)==1000000);before=writes;check(esp_spi_transfer(2,tx,0,1,100)==-22&&writes==before);transfer(tx,rx,65,0,1);check(!esp_spi_deinit(2));
 fault=1;while fault<=5 {check(esp_spi_init(2,4,5,6,1000000,fault&3)==1000000);fill(tx,rx,64);running=1;launched=0;updated=0;chunk=0;tx_now=1;let result=esp_spi_transfer(2,tx,rx,64,1000);running=0;let wanted=-110;if fault==5{wanted=-5;}check(result==wanted&&esp_spi_status(2)==wanted&&!esp_spi_transferred(2)&&!load64(esp_spi_states+8)&&ps==0x1888);i=0;while i<80{check(load8(rx+i)==90);i=i+1;}let saved_fault=fault;fault=0;transfer(tx,rx,3,1,1);fault=saved_fault;check(!esp_spi_deinit(2));fault=fault+1;}
 fault=7;check(esp_spi_init(2,4,5,6,1000000,0)==1000000);fill(tx,rx,64);running=1;launched=0;updated=0;chunk=0;tx_now=1;check(esp_spi_transfer(2,tx,rx,64,1)==-110);running=0;check(!esp_spi_transferred(2)&&esp_spi_status(2)==-110);i=0;while i<80{check(load8(rx+i)==90);i=i+1;}check(!esp_spi_deinit(2));
 fault=6;check(esp_spi_init(2,4,5,6,1000000,0)==1000000);fill(tx,rx,65);running=1;launched=0;updated=0;chunk=0;tx_now=1;let before_time=cycle;check(esp_spi_transfer(2,tx,rx,65,1000)==-110);check(cycle-before_time<=1100);running=0;check(esp_spi_transferred(2)==64&&esp_spi_status(2)==-110);verify_rx(rx,64,1);check(!esp_spi_deinit(2));fault=0;
 before=writes;foreign=1;check(esp_spi_init(2,4,5,6,1000000,0)==-95&&esp_spi_transfer(2,tx,rx,1,100)==-95&&esp_spi_deinit(2)==-95&&esp_spi_transferred(2)==-95&&esp_spi_status(2)==-95);foreign=0;check(writes==before&&writes==load64(expected+16));let out=alloc(16);store64(out,checks);store64(out+8,writes);return syscall(1,1,out,16,0,0,0)!=16;}
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
  source=w/'model.flex';source.write_text(f'import "{root}/scripts/lib/build.flex";\nimport "{root}/lib/platform/{chip}-spi.flex";\n'+F);binary=w/'model';subprocess.run([a.compiler,str(source),'-o',str(binary)],check=True);checks,writes=struct.unpack('<QQ',subprocess.check_output([str(binary),str(expected)],timeout=60));cases.append(dict(chip=chip,checks=checks,exact_writes=writes,CPU_execution=False,physical_hardware=False));print(chip,checks,'SPI2 header/transaction checks,',writes,'exact writes')
 (a.work/'report.json').write_text(json.dumps(dict(pass_all=True,cases=cases,reference='ESP-IDF v5.5.1 primary SPI/GPIO/clock headers',physical_hardware=False),indent=2)+'\n')
if __name__=='__main__':main()
