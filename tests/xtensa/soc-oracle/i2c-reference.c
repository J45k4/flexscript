#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>
#include "i2c_struct.h"
#include "i2c_reg.h"
#include "dport_reg.h"
#include "gpio_sig_map.h"
#include "gpio_reg.h"
#include "io_mux_reg.h"
#include "interrupts.h"
static uint64_t values[96];static unsigned nv;
static void v(uint64_t x){values[nv++]=x;}
static uint32_t cmd(unsigned op,unsigned n,unsigned check,unsigned nack){i2c_dev_t d={0};d.command[0].op_code=op;d.command[0].byte_num=n;d.command[0].ack_en=check;d.command[0].ack_val=nack;return d.command[0].val;}
int main(void){
 v(REG_I2C_BASE(0));v(REG_I2C_BASE(1));v(0x6001301c);v(0x6002701c);
 v(DPORT_PERIP_CLK_EN_REG);v(DPORT_PERIP_RST_EN_REG);v(DPORT_I2C_EXT0_CLK_EN);v(DPORT_I2C_EXT1_CLK_EN);
 v(offsetof(i2c_dev_t,ctr));v(offsetof(i2c_dev_t,status_reg));v(offsetof(i2c_dev_t,timeout));v(offsetof(i2c_dev_t,slave_addr));v(offsetof(i2c_dev_t,fifo_conf));v(offsetof(i2c_dev_t,fifo_data));v(offsetof(i2c_dev_t,int_raw));v(offsetof(i2c_dev_t,int_clr));v(offsetof(i2c_dev_t,int_ena));v(offsetof(i2c_dev_t,int_status));v(offsetof(i2c_dev_t,command));v(I2C_COMMAND0_DONE);
 v(I2C_MS_MODE);v(I2C_CLK_EN);v(I2C_SDA_FORCE_OUT|I2C_SCL_FORCE_OUT);v(I2C_RX_FIFO_RST);v(I2C_TX_FIFO_RST);v(I2C_RXFIFO_CNT_V);v(I2C_RXFIFO_CNT_S);v(I2C_TXFIFO_CNT_V);v(I2C_TXFIFO_CNT_S);v(I2C_BUS_BUSY);v(I2C_ARB_LOST);v(I2C_TIME_OUT);
 v(I2C_ACK_ERR_INT_RAW);v(I2C_TIME_OUT_INT_RAW);v(I2C_ARBITRATION_LOST_INT_RAW);v(I2C_TRANS_COMPLETE_INT_RAW);v(I2C_END_DETECT_INT_RAW);v(I2C_SLAVE_TRAN_COMP_INT_RAW);v(I2C_MASTER_TRAN_COMP_INT_RAW);v(I2C_TRANS_START_INT_RAW);v(I2C_RXFIFO_OVF_INT_RAW);v(ETS_I2C_EXT0_INTR_SOURCE);v(ETS_I2C_EXT1_INTR_SOURCE);v(DPORT_PRO_MAC_INTR_MAP_REG);
 v(GPIO_FUNC0_IN_SEL_CFG_REG);v(GPIO_FUNC0_OUT_SEL_CFG_REG);v(IO_MUX_GPIO21_REG);v(IO_MUX_GPIO22_REG);v(IO_MUX_GPIO19_REG);v((2<<MCU_SEL_S)|FUN_IE|FUN_PU);v(GPIO_ENABLE_W1TS_REG);v(GPIO_PIN0_REG);v(GPIO_OUT_W1TS_REG);v(GPIO_OUT_W1TC_REG);v(I2CEXT0_SCL_OUT_IDX);v(I2CEXT0_SDA_OUT_IDX);v(I2CEXT1_SCL_OUT_IDX);v(I2CEXT1_SDA_OUT_IDX);
 v(offsetof(i2c_dev_t,scl_low_period));v(offsetof(i2c_dev_t,scl_high_period));v(offsetof(i2c_dev_t,sda_hold));v(offsetof(i2c_dev_t,sda_sample));v(offsetof(i2c_dev_t,scl_start_hold));v(offsetof(i2c_dev_t,scl_rstart_setup));v(offsetof(i2c_dev_t,scl_stop_hold));v(offsetof(i2c_dev_t,scl_stop_setup));v(offsetof(i2c_dev_t,scl_filter_cfg));v(offsetof(i2c_dev_t,sda_filter_cfg));v(0x3ff40078);v((21<<20)|(21<<14)|(4<<5)|11);v(I2C_SLAVE_ADDRESSED);v(I2C_SLAVE_RW);v(I2C_TRANS_START);v(I2C_NONFIFO_EN);v(I2C_FIFO_ADDR_CFG_EN);v(I2C_ADDR_10BIT_EN);v(I2C_SAMPLE_SCL_LEVEL);v(cmd(4,0,0,0));v(cmd(3,0,0,0));v(cmd(0,0,0,0));v(I2C_TX_LSB_FIRST);v(I2C_RX_LSB_FIRST);
 v(cmd(1,1,0,0));v(cmd(2,1,0,1));v(cmd(2,1,0,0));v(cmd(1,1,1,0));i2c_dev_t unusual={0};unusual.command[0].op_code=1;unusual.command[0].byte_num=1;unusual.command[0].ack_en=1;unusual.command[0].ack_exp=1;v(unusual.command[0].val);
 uint64_t header[4]={UINT64_C(0x4932434d4f440001),nv,50,448};if(fwrite(header,sizeof header,1,stdout)!=1 || fwrite(values,8,nv,stdout)!=nv)return 1;
 const unsigned txsizes[5]={0,1,2,29,30},rxsizes[5]={0,1,2,31,32},halves[3]={4000,400,100};
 for(unsigned bus=0;bus<2;bus++)for(unsigned a=0;a<5;a++)for(unsigned b=0;b<5;b++){
  unsigned seed=bus*71+a*13+b*17,tn=txsizes[a],rn=rxsizes[b],half=halves[(a+b)%3],addr=8+seed%112;
  i2c_dev_t hw={0};hw.ctr.val=I2C_MS_MODE|I2C_CLK_EN|I2C_SDA_FORCE_OUT|I2C_SCL_FORCE_OUT;hw.scl_low_period.period=half-1;hw.scl_high_period.period=half-7;hw.sda_hold.time=half/2;hw.sda_sample.time=half/2;hw.scl_start_hold.time=half;hw.scl_rstart_setup.time=half;hw.scl_stop_hold.time=half;hw.scl_stop_setup.time=half;
  uint8_t tx[32]={0},rx[32]={0},wire[64][3]={{0}};for(unsigned i=0;i<32;i++){tx[i]=(seed+i*37)^0xa6;rx[i]=(seed+i*53)^0x59;}
  unsigned ci=0,wi=0;hw.command[ci++].val=cmd(0,0,0,0);hw.command[ci++].val=cmd(1,tn+1,1,0);wire[wi][0]=0;wire[wi][1]=(addr<<1)|(!tn && rn);wi++;
  for(unsigned i=0;i<tn;i++){wire[wi][0]=0;wire[wi][1]=tx[i];wi++;}
  if(tn && rn){hw.command[ci++].val=cmd(0,0,0,0);hw.command[ci++].val=cmd(1,1,1,0);wire[wi][1]=(addr<<1)|1;wi++;}
  if(rn>1){hw.command[ci++].val=cmd(2,rn-1,0,0);}if(rn){hw.command[ci++].val=cmd(2,1,0,1);}hw.command[ci].val=cmd(3,0,0,0);for(unsigned i=ci+1;i<16;i++)hw.command[i].val=cmd(4,0,0,0);
  for(unsigned i=0;i<rn;i++){wire[wi][0]=1;wire[wi][1]=rx[i];wire[wi][2]=i==rn-1;wi++;}
  uint64_t f[16]={bus,addr,tn,rn,half,hw.ctr.val,hw.scl_low_period.val,hw.scl_high_period.val,hw.sda_hold.val,hw.sda_sample.val,hw.scl_start_hold.val,hw.scl_rstart_setup.val,hw.scl_stop_setup.val,hw.scl_stop_hold.val,ci,wi};uint32_t commands[16];for(unsigned i=0;i<16;i++)commands[i]=hw.command[i].val;
  if(fwrite(f,sizeof f,1,stdout)!=1 || fwrite(commands,sizeof commands,1,stdout)!=1 || fwrite(tx,32,1,stdout)!=1 || fwrite(rx,32,1,stdout)!=1 || fwrite(wire,sizeof wire,1,stdout)!=1)return 1;
 }
 return 0;
}
