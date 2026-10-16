#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include "i2s_struct.h"
#include "i2s_reg.h"
#include "dport_reg.h"
#include "gpio_sig_map.h"
static uint64_t v[64]; static unsigned count;
#define V(x) (v[count++]=(x))
#define O(x) V(offsetof(i2s_dev_t,x))
static uint32_t clock_word(unsigned hz,unsigned bits) {
 uint64_t unit=(uint64_t)hz*bits*8,best=UINT64_MAX; unsigned ba=1,bn=0,bb=0;
 for(unsigned n=160000000/unit;n<=160000000/unit+1;n++)for(unsigned a=1;a<=63;a++)for(unsigned b=0;b<a;b++) {
  int64_t difference=(int64_t)160000000*a-(int64_t)unit*(n*a+b);uint64_t error=llabs(difference);
  if(best==UINT64_MAX || error*ba<best*a){best=error;ba=a;bn=n;bb=b;}
 }
 i2s_dev_t d={0};d.clkm_conf.clk_en=1;d.clkm_conf.clkm_div_num=bn;d.clkm_conf.clkm_div_a=ba;d.clkm_conf.clkm_div_b=bb;return d.clkm_conf.val;
}
int main(void){
 V(REG_I2S_BASE(0));V(REG_I2S_BASE(1));V(DPORT_PERIP_CLK_EN_REG);V(DPORT_PERIP_RST_EN_REG);V(DPORT_I2S0_CLK_EN);V(DPORT_I2S1_CLK_EN);
 O(conf);O(int_raw);O(int_ena);O(int_clr);O(fifo_conf);O(rx_eof_num);O(conf_chan);O(out_link);O(in_link);O(lc_conf);O(conf1);O(conf2);O(clkm_conf);O(sample_rate_conf);O(pdm_conf);O(state);
 V(I2S_TX_RESET);V(I2S_RX_RESET);V(I2S_OUT_RST);V(I2S_IN_RST);V(I2S_TX_START);V(I2S_RX_START);V(I2S_OUTLINK_START);V(I2S_OUTLINK_STOP);V(I2S_OUT_EOF_INT_RAW);V(I2S_IN_SUC_EOF_INT_RAW);V(I2S_OUT_DSCR_ERR_INT_RAW);V(I2S_IN_DSCR_ERR_INT_RAW);V(I2S_TX_IDLE);V(I2S_SIG_LOOPBACK);V(I2S_TX_SLAVE_MOD);V(I2S_RX_SLAVE_MOD);
 V(I2S0O_DATA_OUT23_IDX);V(I2S0I_DATA_IN15_IDX);V(I2S1O_DATA_OUT23_IDX);V(I2S1I_DATA_IN15_IDX);V(I2S0O_BCK_OUT_IDX);V(I2S0O_WS_OUT_IDX);V(I2S0I_BCK_OUT_IDX);V(I2S0I_WS_OUT_IDX);V(I2S1O_BCK_OUT_IDX);V(I2S1O_WS_OUT_IDX);V(I2S1I_BCK_OUT_IDX);V(I2S1I_WS_OUT_IDX);V(0x3ff44130);V(0x3ff44530);
 uint64_t header[4]={UINT64_C(0x493253444d410001),count,72,128};if(fwrite(header,sizeof header,1,stdout)!=1 || fwrite(v,8,count,stdout)!=count)return 1;
 const unsigned rates[]={8000,16000,44100,48000,96000,192000};
 for(unsigned bus=0;bus<2;bus++)for(unsigned mode=1;mode<=3;mode++)for(unsigned bits=16;bits<=32;bits+=16)for(unsigned rate=0;rate<6;rate++){
  i2s_dev_t d={0};d.conf.tx_msb_shift=1;d.conf.rx_msb_shift=1;d.conf.tx_msb_right=bits==16;d.conf.rx_msb_right=bits==16;d.conf.sig_loopback=mode==3;d.conf.rx_slave_mod=mode==3;
  d.fifo_conf.rx_data_num=32;d.fifo_conf.tx_data_num=32;d.fifo_conf.dscr_en=1;d.fifo_conf.tx_fifo_mod_force_en=1;d.fifo_conf.rx_fifo_mod_force_en=1;d.fifo_conf.tx_fifo_mod=bits==32?2:0;d.fifo_conf.rx_fifo_mod=bits==32?2:0;
  d.lc_conf.check_owner=1;d.lc_conf.out_auto_wrback=1;d.lc_conf.out_eof_mode=1;d.conf1.tx_stop_en=1;d.conf1.tx_pcm_bypass=1;d.conf1.rx_pcm_bypass=1;
  d.sample_rate_conf.tx_bck_div_num=4;d.sample_rate_conf.rx_bck_div_num=4;d.sample_rate_conf.tx_bits_mod=bits;d.sample_rate_conf.rx_bits_mod=bits;
  uint32_t clk=clock_word(rates[rate],bits);unsigned a=(clk>>14)&63,b=(clk>>8)&63,n=clk&255;
  unsigned bck=bus?I2S1O_BCK_OUT_IDX:I2S0O_BCK_OUT_IDX,ws=bus?I2S1O_WS_OUT_IDX:I2S0O_WS_OUT_IDX;if(mode==1){bck=bus?I2S1I_BCK_OUT_IDX:I2S0I_BCK_OUT_IDX;ws=bus?I2S1I_WS_OUT_IDX:I2S0I_WS_OUT_IDX;}
  uint64_t f[16]={bus,mode,bits,rates[rate],d.conf.val,d.fifo_conf.val,d.lc_conf.val,d.conf1.val,clk,d.sample_rate_conf.val,bus?I2S1O_DATA_OUT23_IDX:I2S0O_DATA_OUT23_IDX,bus?I2S1I_DATA_IN15_IDX:I2S0I_DATA_IN15_IDX,bck,ws,(uint64_t)160000000*a/((n*a+b)*bits*8),0};if(fwrite(f,sizeof f,1,stdout)!=1)return 1;
 }
 return 0;
}
