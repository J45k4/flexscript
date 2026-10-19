#!/usr/bin/env python3
"""Pinned I2C HAL timing/open-drain code plus C-header MMIO transaction oracle.

Native scripted slave/status inputs test driver policy; no physical bus or
C6 CPU execution is inferred from them.
"""
import argparse,json,re,shutil,struct,subprocess
from pathlib import Path
C=r'''
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include "soc/i2c_reg.h"
#include "soc/gpio_reg.h"
#include "soc/io_mux_reg.h"
#include "soc/gpio_sig_map.h"
#ifdef C6
#include "soc/pcr_reg.h"
#define TOUT_REG I2C_TO_REG
#else
#include "soc/system_reg.h"
#define TOUT_REG I2C_TO_REG
#endif
#define HAL_ASSERT(x) assert(x)
typedef struct{uint32_t clkm_div,scl_low,scl_wait_high,scl_high,sda_hold,sda_sample,setup,hold,tout;} i2c_hal_clk_config_t;
typedef struct{union{struct{uint32_t sda_force_out:1,scl_force_out:1,other:30;};uint32_t val;}ctr;}i2c_dev_t;
/*HAL_FUNCTIONS*/
static uint64_t trace[32768][3];static unsigned count;static i2c_hal_clk_config_t timing;static uint32_t control,mask;static unsigned gpio_atomic=1;
static uint32_t get(uint32_t a){for(unsigned i=count;i;i--)if(trace[i-1][0]==a){uint32_t v=trace[i-1][1];if(a==I2C_CTR_REG(0))v&=~(I2C_CONF_UPGATE|I2C_TRANS_START|I2C_FSM_RST);return v;}
#ifndef C6
 if(a==SYSTEM_PERIP_CLK_EN0_REG){return 0xcafe0080;}if(a==SYSTEM_PERIP_RST_EN0_REG){return 0xbabe0000;}
#endif
 return 0xa5a5a5a5;}
static void put(uint32_t a,uint32_t v,unsigned atomic){trace[count][0]=a;trace[count][1]=v;trace[count++][2]=atomic;}
static void update(uint32_t a,uint32_t m,uint32_t v){put(a,(get(a)&~m)|(v&m),1);}
static void reset(void){
#ifdef C6
 update(PCR_I2C_CONF_REG,PCR_I2C_CLK_EN|PCR_I2C_RST_EN,PCR_I2C_CLK_EN|PCR_I2C_RST_EN);update(PCR_I2C_CONF_REG,PCR_I2C_RST_EN,0);
 update(PCR_I2C_SCLK_CONF_REG,PCR_I2C_SCLK_DIV_NUM_M|PCR_I2C_SCLK_DIV_A_M|PCR_I2C_SCLK_DIV_B_M|PCR_I2C_SCLK_SEL|PCR_I2C_SCLK_EN,(timing.clkm_div-1)|PCR_I2C_SCLK_EN);
#else
 update(SYSTEM_PERIP_CLK_EN0_REG,SYSTEM_I2C_EXT0_CLK_EN,SYSTEM_I2C_EXT0_CLK_EN);update(SYSTEM_PERIP_RST_EN0_REG,SYSTEM_I2C_EXT0_RST,SYSTEM_I2C_EXT0_RST);update(SYSTEM_PERIP_RST_EN0_REG,SYSTEM_I2C_EXT0_RST,0);put(I2C_CLK_CONF_REG(0),(timing.clkm_div-1)|I2C_SCLK_ACTIVE,1);
#endif
 put(I2C_CTR_REG(0),control,1);put(I2C_SCL_LOW_PERIOD_REG(0),timing.scl_low-1,1);put(I2C_SCL_HIGH_PERIOD_REG(0),timing.scl_high|(timing.scl_wait_high<<I2C_SCL_WAIT_HIGH_PERIOD_S),1);put(I2C_SDA_HOLD_REG(0),timing.sda_hold-1,1);put(I2C_SDA_SAMPLE_REG(0),timing.sda_sample-1,1);put(I2C_SCL_START_HOLD_REG(0),timing.hold-1,1);put(I2C_SCL_RSTART_SETUP_REG(0),timing.setup-1,1);put(I2C_SCL_STOP_HOLD_REG(0),timing.hold-1,1);put(I2C_SCL_STOP_SETUP_REG(0),timing.setup-1,1);put(TOUT_REG(0),timing.tout|I2C_TIME_OUT_EN,1);put(I2C_FILTER_CFG_REG(0),(7<<I2C_SCL_FILTER_THRES_S)|(7<<I2C_SDA_FILTER_THRES_S)|I2C_SCL_FILTER_EN|I2C_SDA_FILTER_EN,1);
 uint32_t fifo=I2C_FIFO_PRT_EN|(4<<I2C_TXFIFO_WM_THRHD_S)|(11<<I2C_RXFIFO_WM_THRHD_S);put(I2C_FIFO_CONF_REG(0),fifo|I2C_RX_FIFO_RST|I2C_TX_FIFO_RST,1);put(I2C_FIFO_CONF_REG(0),fifo,1);put(I2C_INT_ENA_REG(0),0,1);put(I2C_INT_CLR_REG(0),mask,1);put(I2C_CTR_REG(0),control|I2C_CONF_UPGATE,1);
}
static void mux(unsigned p){uint32_t a=IO_MUX_GPIO0_REG+p*4;put(a,(get(a)&~MCU_SEL_M)|(FUNC_MTMS_GPIO4<<MCU_SEL_S)|FUN_IE,1);}
static void pull(unsigned p,unsigned high){update(IO_MUX_GPIO0_REG+p*4,FUN_PU|FUN_PD,high?FUN_PU:0);}
static void output(unsigned p){mux(p);put(GPIO_FUNC0_OUT_SEL_CFG_REG+p*4,SIG_GPIO_OUT_IDX|GPIO_FUNC0_OEN_SEL,gpio_atomic);put(GPIO_ENABLE_W1TS_REG,1u<<p,gpio_atomic);}
static void route(void){unsigned pins[]={5,4},signals[]={I2CEXT0_SCL_OUT_IDX,I2CEXT0_SDA_OUT_IDX};for(unsigned i=0;i<2;i++){output(pins[i]);put(GPIO_FUNC0_OUT_SEL_CFG_REG+pins[i]*4,signals[i]|GPIO_FUNC0_OEN_SEL,1);mux(pins[i]);put(GPIO_FUNC0_IN_SEL_CFG_REG+signals[i]*4,pins[i]|GPIO_SIG0_IN_SEL,1);}}
static void init(unsigned hz){i2c_ll_master_cal_bus_clk(40000000,hz,&timing);reset();update(GPIO_PIN0_REG+4*4,GPIO_PIN0_PAD_DRIVER,GPIO_PIN0_PAD_DRIVER);update(GPIO_PIN0_REG+5*4,GPIO_PIN0_PAD_DRIVER,GPIO_PIN0_PAD_DRIVER);put(GPIO_OUT_W1TS_REG,1u<<4,1);put(GPIO_OUT_W1TS_REG,1u<<5,1);pull(4,1);pull(5,1);route();}
static void deinit(void){reset();put(GPIO_OUT_W1TS_REG,1u<<4,1);put(GPIO_OUT_W1TS_REG,1u<<5,1);mux(4);put(GPIO_ENABLE_W1TC_REG,1u<<4,1);pull(4,0);mux(5);put(GPIO_ENABLE_W1TC_REG,1u<<5,1);pull(5,0);update(GPIO_PIN0_REG+4*4,GPIO_PIN0_PAD_DRIVER,0);update(GPIO_PIN0_REG+5*4,GPIO_PIN0_PAD_DRIVER,0);
#ifdef C6
 update(PCR_I2C_SCLK_CONF_REG,PCR_I2C_SCLK_EN,0);update(PCR_I2C_CONF_REG,PCR_I2C_CLK_EN,0);
#else
 update(I2C_CLK_CONF_REG(0),I2C_SCLK_ACTIVE,0);update(SYSTEM_PERIP_CLK_EN0_REG,SYSTEM_I2C_EXT0_CLK_EN,0);
#endif
}
static unsigned command(unsigned index,unsigned op,unsigned n,unsigned ack){i2c_ll_hw_cmd_t cmd={.val=0};cmd.op_code=op;cmd.byte_num=n;cmd.ack_en=!!(ack&256);cmd.ack_exp=!!(ack&512);cmd.ack_val=!!(ack&1024);put(I2C_COMD0_REG(0)+index*4,cmd.val,0);return index+1;}
static void transfer(unsigned address,unsigned tx,unsigned rx,unsigned fault){update(I2C_FIFO_CONF_REG(0),I2C_RX_FIFO_RST|I2C_TX_FIFO_RST,I2C_RX_FIFO_RST|I2C_TX_FIFO_RST);update(I2C_FIFO_CONF_REG(0),I2C_RX_FIFO_RST|I2C_TX_FIFO_RST,0);put(I2C_INT_CLR_REG(0),mask,0);for(unsigned i=0;i<8;i++)command(i,I2C_LL_CMD_END,0,0);unsigned cmd=command(0,I2C_LL_CMD_RESTART,0,0);put(I2C_DATA_REG(0),(address<<1)|(!tx&&rx?1:0),0);for(unsigned i=0;i<tx;i++)put(I2C_DATA_REG(0),(i*37+11)&255,0);cmd=command(cmd,I2C_LL_CMD_WRITE,tx+1,1<<8);if(tx&&rx){cmd=command(cmd,I2C_LL_CMD_RESTART,0,0);put(I2C_DATA_REG(0),(address<<1)|1,0);cmd=command(cmd,I2C_LL_CMD_WRITE,1,1<<8);}if(rx>1)cmd=command(cmd,I2C_LL_CMD_READ,rx-1,0);if(rx)cmd=command(cmd,I2C_LL_CMD_READ,1,1<<10);command(cmd,I2C_LL_CMD_STOP,0,0);update(I2C_CTR_REG(0),I2C_CONF_UPGATE,I2C_CONF_UPGATE);if(fault!=12)update(I2C_CTR_REG(0),I2C_TRANS_START,I2C_TRANS_START);if(fault)reset();else put(I2C_INT_CLR_REG(0),mask,0);}
static void recovery(unsigned pulses,unsigned stop){reset();update(GPIO_PIN0_REG+4*4,GPIO_PIN0_PAD_DRIVER,GPIO_PIN0_PAD_DRIVER);update(GPIO_PIN0_REG+5*4,GPIO_PIN0_PAD_DRIVER,GPIO_PIN0_PAD_DRIVER);pull(4,1);pull(5,1);put(GPIO_OUT_W1TS_REG,1u<<4,0);put(GPIO_OUT_W1TS_REG,1u<<5,0);gpio_atomic=0;output(4);output(5);gpio_atomic=1;for(unsigned i=0;i<pulses;i++){put(GPIO_OUT_W1TC_REG,1u<<5,0);put(GPIO_OUT_W1TS_REG,1u<<5,0);}if(stop){put(GPIO_OUT_W1TC_REG,1u<<5,0);put(GPIO_OUT_W1TC_REG,1u<<4,0);put(GPIO_OUT_W1TS_REG,1u<<5,0);put(GPIO_OUT_W1TS_REG,1u<<4,0);}put(GPIO_OUT_W1TS_REG,1u<<4,0);put(GPIO_OUT_W1TS_REG,1u<<5,0);route();reset();}
int main(void){
#ifdef C6
 uint64_t h[16]={0x40830000,DR_REG_I2C_EXT_BASE};mask=0x7ffff;
#else
 uint64_t h[16]={0x3fca0000,DR_REG_I2C_EXT_BASE};mask=0x3ffff;
#endif
 i2c_dev_t hw={0};i2c_ll_enable_pins_open_drain(&hw,true);control=I2C_MS_MODE|I2C_CLK_EN|I2C_ARBITRATION_EN|hw.ctr.val;h[3]=control;h[4]=mask;h[5]=I2C_ARBITRATION_LOST_INT_RAW;h[6]=I2C_NACK_INT_RAW;h[7]=I2C_TIME_OUT_INT_RAW;h[8]=I2C_SCL_ST_TO_INT_RAW;h[9]=I2C_SCL_MAIN_ST_TO_INT_RAW;h[10]=I2C_RXFIFO_OVF_INT_RAW;h[11]=I2C_TXFIFO_OVF_INT_RAW;h[12]=I2C_TRANS_COMPLETE_INT_RAW;h[13]=I2C_RXFIFO_CNT_S;h[14]=I2C_COMMAND0_DONE;
 unsigned rates[]={10000,20000,39062,39063,79999,80000,100000,123456,400000};for(unsigned r=0;r<9;r++){init(rates[r]);for(unsigned tx=0;tx<=31;tx++)for(unsigned rx=0;rx<=32;rx++){if(tx>30&&rx)continue;transfer(0x50,tx,rx,0);}deinit();}
 // Explicit address edge cases and memory-overlap consumers.
 init(100000);transfer(0,1,1,0);transfer(127,1,1,0);transfer(0x50,4,4,0);transfer(0x50,4,4,0);deinit();
 for(unsigned fault=1;fault<=12;fault++){init(100000);transfer(0x50,3,4,fault);transfer(0x50,1,1,0);deinit();}
 init(100000);for(unsigned n=0;n<=9;n++)recovery(n,1);recovery(9,0);recovery(0,0);recovery(2,1);recovery(3,0);recovery(1,1);recovery(1,0);recovery(1,0);deinit();
 h[2]=count;fwrite(h,sizeof h,1,stdout);fwrite(trace,sizeof trace[0],count,stdout);return ferror(stdout)?1:0;
}
'''
# All nine rates are checked for timing; every FIFO size pair needs only one
# timing instance. Keep the trace compact enough to inspect and retain.
C=C.replace('trace[32768]','trace[65536]').replace('for(unsigned tx=0;tx<=31;tx++)for(unsigned rx=0;rx<=32;rx++)','for(unsigned tx=0;tx<=(r==6?31:1);tx++)for(unsigned rx=0;rx<=(r==6?32:1);rx++)')
F=r'''
global expected=0;global regs=0;global writes=0;global checks=0;global ps=0x1888;global cycle=0;global busy=0;global fault=0;global active=0;global wanted_rx=0;global popped=0;global foreign=0;global state_once=0;global rec=0;global rec_release=0;global rec_rises=0;global rec_gpio=0;global rec_scl=1;global rec_stop=0;global rec_fault=0;global rec_reads=0;global guard_start=0;global rec_low_at=0;global poll_observations=0;
fn check(ok){checks=checks+1;if !ok{h_print(2,h_cat3("I2C header check ",h_int(checks)," failed\n"));h_print(2,h_cat3("writes=",h_int(writes),h_cat3(" fault=",h_int(fault),"\n")));syscall(60,1,0,0,0,0,0);}return 0;}
fn esp32_state(){if foreign{return 17;}return load64(expected);}
fn esp32_cycles(){if fault||rec&&(rec_fault==1||rec_fault==3&&rec_rises>=3||rec_fault==4&&rec_stop){cycle=cycle+100;}else{cycle=cycle+1;}if active&&fault&&cycle-guard_start>2000{check(0);}return cycle&4294967295;}
fn esp32_irq_save(){let old=ps;ps=ps&~8;return old;}
fn esp32_irq_restore(value){ps=value;return 0;}
fn ibase(){return load64(expected+8);}
fn esp32_load32(address){let base=ibase();if address==esp32_state()+16{return busy==8;}if address==rv_hal_gpio+0x3c{if busy==9{return 0;}if rec {let value=0;if rec_rises>=rec_release {value=value|(1<<4);}let high=1;if rec_fault==1||rec_fault==3&&rec_rises>=3||rec_fault==4&&rec_stop {high=0;}if rec_fault==2&&rec_rises==1&&rec_reads<3 {rec_reads=rec_reads+1;high=0;}if high{value=value|(1<<5);}return value;}return (1<<4)|(1<<5);}
 if address==base+40{return busy==1;}if address==base+8{if busy==2{return 16;}if busy==3{return 1<<8;}if busy==4{return 1<<18;}if active{let n=wanted_rx-popped;if fault==9{n=n+1;}return n<<load64(expected+104);}return 0;}
 if address==base+32{if !active{return 0;}poll_observations=poll_observations+1;check(poll_observations<=64);if fault==1{return load64(expected+48);}if fault==2{return load64(expected+40)|load64(expected+48);}if fault>=3&&fault<=7{return load64(expected+56+(fault-3)*8);}if fault==8{return 0;}return load64(expected+96);}
 if address==base+28&&active{let byte=(popped*53+167)&255;popped=popped+1;return byte;}
 let value=0xa5a5a5a5;let i=writes;let found=0;while i&&!found{i=i-1;if load64(regs+i*16)==address{value=load64(regs+i*16+8);found=1;}}
 if address>=base+88&&address<base+120 {if active&&fault!=10 {if !(fault==11&&address==base+88){value=value|load64(expected+112);}}return value;}
 if address==base+4{if !found{value=0;}value=value&~((1<<5)|(1<<10)|(1<<11));if busy==5{value=value|(1<<5);}if busy==6{value=value|(1<<10);}}
 if !found&&address==0x600c0010{value=0xcafe0080;}if !found&&address==0x600c0018{value=0xbabe0000;}
 if busy==7{if address==0x600c0018{value=value|128;}if address==0x60096020{value=value|2;}}return value;}
fn esp32_store32(address,value){check(writes<load64(expected+16));let row=expected+128+writes*24;check(address==load64(row));check((value&4294967295)==load64(row+8));if load64(row+16){check(!(ps&8));}store64(regs+writes*16,address);store64(regs+writes*16+8,value&4294967295);writes=writes+1;
 if rec {if address==rv_hal_gpio+0x554+5*4 {if value==(128|512){rec_gpio=1;}else{rec_gpio=0;}}if rec_gpio&&address==rv_hal_gpio+12&&(value&(1<<5)){rec_scl=0;rec_low_at=cycle;}if rec_gpio&&address==rv_hal_gpio+12&&(value&(1<<4)){rec_stop=1;}if rec_gpio&&address==rv_hal_gpio+8&&(value&(1<<5))&&!rec_scl{if rec_fault!=5&&rec_fault!=6{check(cycle-rec_low_at>=8000);}rec_scl=1;if !rec_stop{rec_rises=rec_rises+1;}}}
 if address==ibase()+4 {if value&(1<<5){active=1;popped=0;poll_observations=0;}else if !(value&(1<<11)){active=0;popped=0;}}if address==ibase()+36&&!(load64(esp_i2c_states+8)){active=0;}return 0;}
fn rate(r){if r==0{return 10000;}if r==1{return 20000;}if r==2{return 39062;}if r==3{return 39063;}if r==4{return 79999;}if r==5{return 80000;}if r==6{return 100000;}if r==7{return 123456;}return 400000;}
fn prepare(tx,rx){let i=0;while i<64{store8(tx+i,(i*37+11)&255);store8(rx+i,90);i=i+1;}return 0;}
fn verify(rx,n){let i=0;while i<n{check(load8(rx+i)==((i*53+167)&255));i=i+1;}while i<64{check(load8(rx+i)==90);i=i+1;}return 0;}
fn transfer(tx,rx,t,n,address){prepare(tx,rx);active=0;wanted_rx=n;popped=0;check(esp_i2c_transfer(0,address,tx,t,rx,n,1000000)==t+n);active=0;check(esp_i2c_transferred(0)==t+n&&!esp_i2c_status(0)&&!load64(esp_i2c_states+8)&&ps==0x1888);verify(rx,n);return 0;}
fn recovery(n,kind,budget,want){rec=1;rec_release=n;rec_rises=0;rec_gpio=0;rec_scl=1;rec_stop=0;rec_fault=kind;rec_reads=0;let before=cycle;let result=esp_i2c_recover(0,budget);rec=0;check(result==want&&esp_i2c_status(0)==want&&!esp_i2c_transferred(0)&&!load64(esp_i2c_states+8)&&ps==0x1888);check(cycle-before<=budget+200);if kind==0&&n<=9{check(rec_rises==n&&rec_stop);}if n==10{check(rec_rises==9&&!rec_stop);}if kind==1{check(!rec_rises&&!rec_stop);}if kind==2{check(rec_rises==2&&rec_stop&&rec_reads==3);}if kind==3{check(rec_rises==3&&!rec_stop);}if kind==4{check(rec_stop&&rec_rises==1);}if kind==5||kind==6{check(rec_rises==1&&!rec_stop);}return 0;}
fn guards(tx,rx){let before=writes;check(esp_i2c_init(1,4,5,100000)==-22&&esp_i2c_init(-1,4,5,100000)==-22&&esp_i2c_init(0,4,4,100000)==-22&&esp_i2c_init(0,rv_hal_reserved_start,5,100000)==-22&&esp_i2c_init(0,4,1<<32,100000)==-22);check(esp_i2c_init(0,4,5,9999)==-22&&esp_i2c_init(0,4,5,400001)==-22);check(esp_i2c_transfer(0,128,tx,1,rx,1,100)==-22&&esp_i2c_transfer(0,-1,tx,1,rx,1,100)==-22&&esp_i2c_transfer(0,0x50,tx,32,0,0,100)==-22&&esp_i2c_transfer(0,0x50,tx,31,rx,1,100)==-22&&esp_i2c_transfer(0,0x50,tx,1,rx,33,100)==-22);check(esp_i2c_transfer(0,0x50,0,1,rx,1,100)==-22&&esp_i2c_transfer(0,0x50,tx,1,1<<32,1,100)==-22&&esp_i2c_transfer(0,0x50,tx,1,rx,1,0)==-22&&esp_i2c_transfer(0,0x50,tx,1,rx,1,2147483648)==-22);check(esp_i2c_recover(0,0)==-22&&esp_i2c_recover(1,100)==-22);check(writes==before&&ps==0x1888);return 0;}
fn main(argc,argv){h_environment(argc,argv);expected=h_read(load64(argv+8));regs=alloc(2097152);let arena=esp32_state()+65536;check(syscall(9,arena,4096,3,50,-1,0)==arena);let tx=arena;let rx=arena+512;check(esp_i2c_base(0)==ibase()&&!esp_i2c_base(1)&&!esp_i2c_base(-1));guards(tx,rx);check(esp_i2c_probe(0,0x50,100)==-19&&esp_i2c_status(0)==-19&&esp_i2c_recover(0,100)==-19);
 busy=1;while busy<=8{let before=writes;check(esp_i2c_init(0,4,5,100000)==-16&&writes==before&&!esp_i2c_states);busy=busy+1;}busy=0;
 let r=0;while r<9 {check(!esp_i2c_init(0,4,5,rate(r)));if !state_once{state_once=esp_i2c_states;}check(state_once==esp_i2c_states);check(eir_control()==load64(expected+24));let before=writes;check(esp_i2c_init(0,4,5,rate(r))==-16&&writes==before);let max_t=1;let max_n=1;if r==6{max_t=31;max_n=32;}let t=0;while t<=max_t{let n=0;while n<=max_n{if t<=30||!n{transfer(tx,rx,t,n,0x50);}n=n+1;}t=t+1;}
  if r==6{before=writes;busy=1;while busy<=9{check(esp_i2c_transfer(0,0x50,tx,1,rx,1,100)==-16&&writes==before);if busy<9{check(esp_i2c_deinit(0)==-16&&writes==before);}busy=busy+1;}busy=0;store64(esp_i2c_states+8,1);check(esp_i2c_probe(0,0x50,100)==-16&&esp_i2c_deinit(0)==-16&&esp_i2c_recover(0,100)==-16);store64(esp_i2c_states+8,0);guards(tx,rx);}
  check(!esp_i2c_deinit(0)&&!esp_i2c_deinit(0));r=r+1;
 }
 check(!esp_i2c_init(0,4,5,100000));transfer(tx,rx,1,1,0);transfer(tx,rx,1,1,127);
 prepare(tx,rx);wanted_rx=4;active=0;check(esp_i2c_transfer(0,0x50,tx,4,tx,4,1000000)==8);active=0;let i=0;while i<4{check(load8(tx+i)==((i*53+167)&255));i=i+1;}prepare(tx,rx);wanted_rx=4;active=0;check(esp_i2c_transfer(0,0x50,tx,4,tx+1,4,1000000)==8);active=0;i=0;while i<4{check(load8(tx+1+i)==((i*53+167)&255));i=i+1;}check(!esp_i2c_deinit(0));
 fault=1;while fault<=12 {check(!esp_i2c_init(0,4,5,100000));prepare(tx,rx);wanted_rx=4;active=0;let budget=1000;if fault==12{budget=1;}if fault==8{cycle=4294967040;}guard_start=cycle;let before_time=cycle;let result=esp_i2c_transfer(0,0x50,tx,3,rx,4,budget);active=0;let want=-5;if fault==1{want=-6;}else if fault==2{want=-11;}else if fault==3||fault==4||fault==5||fault==8||fault==12{want=-110;}check(result==want&&esp_i2c_status(0)==want&&!esp_i2c_transferred(0)&&!load64(esp_i2c_states+8)&&ps==0x1888);check(cycle-before_time<=1100);verify(rx,0);let saved=fault;fault=0;transfer(tx,rx,1,1,0x50);fault=saved;check(!esp_i2c_deinit(0));fault=fault+1;}
 fault=0;check(!esp_i2c_init(0,4,5,100000));let n=0;while n<=9{recovery(n,0,500000,0);n=n+1;}recovery(10,0,500000,-16);recovery(5,1,1000,-110);recovery(2,2,500000,0);recovery(5,3,500000,-110);recovery(1,4,500000,-110);recovery(5,5,1,-110);recovery(5,6,5000,-110);check(!esp_i2c_deinit(0));let before=writes;foreign=1;check(esp_i2c_init(0,4,5,100000)==-95&&esp_i2c_transfer(0,0x50,tx,1,rx,1,100)==-95&&esp_i2c_deinit(0)==-95&&esp_i2c_recover(0,100)==-95);foreign=0;check(writes==before&&writes==load64(expected+16));let out=alloc(16);store64(out,checks);store64(out+8,writes);return syscall(1,1,out,16,0,0,0)!=16;}
'''
def extract(text,name):
 at=text.index('static inline void '+name+'(');start=text.index('{',at);depth=1;end=start+1
 while depth:
  if text[end]=='{':depth+=1
  elif text[end]=='}':depth-=1
  end+=1
 return text[at:end]
def main():
 p=argparse.ArgumentParser();p.add_argument('--compiler',required=True);p.add_argument('--reference',type=Path,required=True);p.add_argument('--work',type=Path,required=True);a=p.parse_args();root=Path(__file__).resolve().parents[2];a.work.mkdir(parents=True,exist_ok=True);cases=[]
 for chip in ('esp32c3','esp32c6'):
  w=a.work/chip;inc=w/'include/soc';inc.mkdir(parents=True,exist_ok=True)
  for folder in ('register/soc','include/soc'):
   for f in (a.reference/'components/soc'/chip/folder).glob('*.h'):shutil.copyfile(f,inc/f.name)
  (inc.parent/'esp_assert.h').write_text('#pragma once\n');(inc.parent/'esp_bit_defs.h').write_text('#pragma once\n#define BIT(n) (1U<<(n))\n#define BIT64(n) (1ULL<<(n))\n')
  hal=(a.reference/f'components/hal/{chip}/include/hal/i2c_ll.h').read_text();functions='\n'.join(extract(hal,n) for n in ['i2c_ll_master_cal_bus_clk','i2c_ll_enable_pins_open_drain']);start=hal.index('typedef union {');end=hal.index('} i2c_ll_hw_cmd_t;',start)+len('} i2c_ll_hw_cmd_t;');functions=hal[start:end]+'\n'+'\n'.join(re.findall(r'^#define I2C_LL_CMD_\w+\s+\d+.*',hal,re.M))+'\n'+functions;source=w/'oracle.c';source.write_text(C.replace('/*HAL_FUNCTIONS*/',functions));oracle=w/'oracle';cmd=['cc','-std=c11','-Wall','-Wextra','-Werror','-I',str(inc.parent),str(source),'-o',str(oracle)]
  if chip=='esp32c6':cmd.insert(1,'-DC6')
  subprocess.run(cmd,check=True);expected=w/'expected.bin';expected.write_bytes(subprocess.check_output([str(oracle)]))
  source=w/'model.flex';source.write_text(f'import "{root}/scripts/lib/build.flex";\nimport "{root}/lib/platform/{chip}-i2c.flex";\n'+F);binary=w/'model';subprocess.run([a.compiler,str(source),'-o',str(binary)],check=True);checks,writes=struct.unpack('<QQ',subprocess.check_output([str(binary),str(expected)],timeout=60));cases.append(dict(chip=chip,checks=checks,exact_writes=writes,CPU_execution=False,physical_hardware=False));print(chip,checks,'I2C header/transaction checks,',writes,'exact writes')
 (a.work/'report.json').write_text(json.dumps(dict(pass_all=True,cases=cases,reference='ESP-IDF v5.5.1 primary I2C/GPIO/clock headers and unmodified HAL functions',physical_hardware=False),indent=2)+'\n')
if __name__=='__main__':main()
