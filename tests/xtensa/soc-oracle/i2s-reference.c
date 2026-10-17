// Reuse the independent C register/clock oracle; never include driver/emitter code.
#define main adapter_reference_main
#include "../../esp32/i2s-oracle/register-reference.c"
#undef main
#include <string.h>
#include "gpio_reg.h"
#include "io_mux_reg.h"
#include "interrupts.h"
#include "esp_rom_lldesc.h"
static uint32_t flags(unsigned size,unsigned length,unsigned eof,unsigned owner){lldesc_t d={0};d.size=size;d.length=length;d.eof=eof;d.owner=owner;uint32_t value;memcpy(&value,&d,4);return value;}
int main(void){
 if(adapter_reference_main())return 1;
 uint64_t v[]={ETS_I2S0_INTR_SOURCE,ETS_I2S1_INTR_SOURCE,DPORT_PRO_MAC_INTR_MAP_REG,IO_MUX_GPIO21_REG,IO_MUX_GPIO25_REG,IO_MUX_GPIO22_REG,IO_MUX_GPIO4_REG,(2u<<MCU_SEL_S)|FUN_IE,GPIO_ENABLE_W1TS_REG,GPIO_ENABLE_W1TC_REG,GPIO_OUT_W1TS_REG,GPIO_OUT_W1TC_REG,I2S_IN_DSCR_EMPTY_INT_RAW,I2S_OUT_TOTAL_EOF_INT_RAW,I2S_IN_DONE_INT_RAW,I2S_OUT_DONE_INT_RAW,I2S_IN_ERR_EOF_INT_RAW,I2S_DSCR_EN,I2S_OUT_AUTO_WRBACK,I2S_CHECK_OWNER,I2S_OUT_EOF_MODE,I2S_RX_FIFO_RESET,I2S_TX_FIFO_RESET,I2S_OUTLINK_PARK,I2S_INLINK_PARK,flags(0,0,0,1),flags(0,0,1,0),flags(0,4095,0,0),flags(4095,0,0,0),0x3ff48070,3u<<27,1u<<27};
 uint64_t h[4]={UINT64_C(0x4932535749524501),sizeof(v)/8,18,512};if(fwrite(h,sizeof h,1,stdout)!=1 || fwrite(v,sizeof v,1,stdout)!=1)return 1;
 const unsigned hz[3]={8000,44100,192000};
 for(unsigned bus=0;bus<2;bus++)for(unsigned width=16;width<=32;width+=16)for(unsigned order=0;order<(width==16?2:1);order++)for(unsigned rate=0;rate<3;rate++){
  unsigned msb_right=width==16?order:0,bytes=width/4*3,points=width*6+1;uint8_t out[512]={0},payload[24]={0},serial[192]={0};
  for(unsigned i=0;i<bytes;i++)payload[i]=(i*37+width*3+bus*19+rate*7)^0xa6;
  unsigned at=0;for(unsigned frame=0;frame<3;frame++)for(unsigned channel=0;channel<2;channel++){
   unsigned byte=frame*(width/4)+channel*(width/8);if(width==16 && !msb_right)byte=frame*4+(1-channel)*2;
   uint32_t value=0;for(unsigned i=0;i<width/8;i++)value|=(uint32_t)payload[byte+i]<<(i*8);
   for(unsigned bit=0;bit<width;bit++)serial[at++]=(value>>(width-1-bit))&1;
  }
  i2s_dev_t d={0};d.conf.tx_msb_shift=1;d.conf.rx_msb_shift=1;d.conf.tx_msb_right=msb_right;d.conf.rx_msb_right=msb_right;d.conf.sig_loopback=1;d.conf.rx_slave_mod=1;
  d.fifo_conf.rx_data_num=32;d.fifo_conf.tx_data_num=32;d.fifo_conf.dscr_en=1;d.fifo_conf.tx_fifo_mod_force_en=1;d.fifo_conf.rx_fifo_mod_force_en=1;d.fifo_conf.tx_fifo_mod=width==32?2:0;d.fifo_conf.rx_fifo_mod=width==32?2:0;
  d.sample_rate_conf.tx_bck_div_num=4;d.sample_rate_conf.rx_bck_div_num=4;d.sample_rate_conf.tx_bits_mod=width;d.sample_rate_conf.rx_bits_mod=width;d.lc_conf.check_owner=1;d.lc_conf.out_auto_wrback=1;d.lc_conf.out_eof_mode=1;d.conf1.tx_stop_en=1;d.conf1.tx_pcm_bypass=1;d.conf1.rx_pcm_bypass=1;
  uint32_t clk=clock_word(hz[rate],width);unsigned a=(clk>>14)&63,b=(clk>>8)&63,n=clk&255;
  uint64_t f[16]={bus,width,hz[rate],clk,d.fifo_conf.val,d.sample_rate_conf.val,d.conf.val,d.conf1.val,d.lc_conf.val,bytes,points,(n*a+b)*4,a*4,msb_right,0,0};memcpy(out,f,sizeof f);memcpy(out+128,payload,bytes);
  // Expand whole samples first, then apply Philips' one-clock WS lead.
  for(unsigned i=0;i<points;i++)out[152+i]=((i/width)&1)*2+(i?serial[i-1]:0);
  if(fwrite(out,sizeof out,1,stdout)!=1)return 1;
 }
 return 0;
}
