#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include "ledc_struct.h"
#include "rmt_struct.h"
#include "ledc_reg.h"
#include "rmt_reg.h"
#include "gpio_sig_map.h"
#include "memory-address.h"
#include "symbol-definition.h"
#define __ASSEMBLER__
#include "dport_reg.h"
int main(void){
 ledc_dev_t led={0};rmt_dev_t rm={0};rmt_symbol_word_t symbol={0};
 uint64_t v[88]={DR_REG_LEDC_BASE,offsetof(ledc_dev_t,channel_group[0]),offsetof(ledc_dev_t,channel_group[1]),offsetof(ledc_dev_t,timer_group[0]),offsetof(ledc_dev_t,timer_group[1]),offsetof(ledc_dev_t,conf),offsetof(ledc_dev_t,int_raw),offsetof(ledc_dev_t,int_ena),offsetof(ledc_dev_t,int_clr),LEDC_DIV_NUM_HSTIMER0_M,LEDC_TICK_SEL_HSTIMER0,LEDC_LSTIMER0_PARA_UP,LEDC_HSTIMER0_PAUSE,LEDC_HSTIMER0_RST,LEDC_SIG_OUT_EN_HSCH0,LEDC_IDLE_LV_HSCH0,LEDC_PARA_UP_LSCH0,0,LEDC_HS_SIG_OUT0_IDX,LEDC_LS_SIG_OUT0_IDX,DPORT_LEDC_CLK_EN,LEDC_CLK_EN,DR_REG_RMT_BASE,offsetof(rmt_dev_t,conf_ch),sizeof(rm.conf_ch[0]),offsetof(rmt_dev_t,status_ch),offsetof(rmt_dev_t,int_raw),offsetof(rmt_dev_t,int_ena),offsetof(rmt_dev_t,int_clr),offsetof(rmt_dev_t,apb_conf),REFERENCE_RMTMEM};
 led.channel_group[0].channel[0].conf1.duty_num=1;led.channel_group[0].channel[0].conf1.duty_cycle=1;led.channel_group[0].channel[0].conf1.duty_inc=1;led.channel_group[0].channel[0].conf1.duty_start=1;v[17]=led.channel_group[0].channel[0].conf1.val;
 rm.conf_ch[0].conf0.clk_en=1;v[31]=rm.conf_ch[0].conf0.val;rm.conf_ch[0].conf0.val=0;rm.conf_ch[0].conf0.mem_size=1;v[32]=rm.conf_ch[0].conf0.val;rm.conf_ch[0].conf0.val=0;rm.conf_ch[0].conf0.mem_pd=1;v[33]=rm.conf_ch[0].conf0.val;
 rm.conf_ch[0].conf1.ref_always_on=1;v[34]=rm.conf_ch[0].conf1.val;rm.apb_conf.fifo_mask=1;v[35]=rm.apb_conf.val;
 rm.conf_ch[0].conf1.val=0;rm.conf_ch[0].conf1.mem_owner=1;v[36]=rm.conf_ch[0].conf1.val;rm.conf_ch[0].conf1.val=0;rm.conf_ch[0].conf1.idle_out_en=1;v[37]=rm.conf_ch[0].conf1.val;rm.conf_ch[0].conf1.val=0;rm.conf_ch[0].conf1.idle_out_lv=1;v[38]=rm.conf_ch[0].conf1.val;
 rm.conf_ch[0].conf1.val=0;rm.conf_ch[0].conf1.tx_start=1;v[39]=rm.conf_ch[0].conf1.val;rm.conf_ch[0].conf1.val=0;rm.conf_ch[0].conf1.rx_en=1;v[40]=rm.conf_ch[0].conf1.val;
 rm.conf_ch[0].conf1.val=0;rm.conf_ch[0].conf1.mem_wr_rst=1;v[41]=rm.conf_ch[0].conf1.val;rm.conf_ch[0].conf1.val=0;rm.conf_ch[0].conf1.mem_rd_rst=1;v[42]=rm.conf_ch[0].conf1.val;rm.conf_ch[0].conf1.val=0;rm.conf_ch[0].conf1.apb_mem_rst=1;v[43]=rm.conf_ch[0].conf1.val;
 rm.conf_ch[0].conf1.val=0;rm.conf_ch[0].conf1.ref_cnt_rst=1;v[44]=rm.conf_ch[0].conf1.val;rm.conf_ch[0].conf1.val=0;rm.conf_ch[0].conf1.rx_filter_en=1;v[45]=rm.conf_ch[0].conf1.val;rm.conf_ch[0].conf1.val=0;rm.conf_ch[0].conf1.rx_filter_thres=255;v[46]=rm.conf_ch[0].conf1.val;
 rm.int_raw.ch0_tx_end=1;v[47]=rm.int_raw.val;rm.int_raw.val=0;rm.int_raw.ch0_rx_end=1;v[48]=rm.int_raw.val;rm.int_raw.val=0;rm.int_raw.ch0_err=1;v[49]=rm.int_raw.val;rm.int_raw.val=0;rm.int_raw.ch0_tx_thr_event=1;v[50]=rm.int_raw.val;
 v[51]=RMT_SIG_OUT0_IDX;v[52]=RMT_SIG_IN0_IDX;v[53]=DPORT_RMT_CLK_EN;v[54]=DPORT_PERIP_CLK_EN_REG;v[55]=DPORT_PERIP_RST_EN_REG;v[56]=offsetof(rmt_dev_t,conf_ch[1])-offsetof(rmt_dev_t,conf_ch[0]);
 for(unsigned i=0;i<16;i++){symbol.level0=i&1;symbol.duration0=3+i*11;symbol.level1=!(i&1);symbol.duration1=5+i*17;v[57+i]=symbol.val;}
 v[73]=LEDC_DUTY_START_HSCH0;for(unsigned blocks=1;blocks<=8;blocks++){rm.conf_ch[0].conf0.val=0;rm.conf_ch[0].conf0.mem_size=blocks;v[73+blocks]=rm.conf_ch[0].conf0.val;}
 uint64_t h[2]={UINT64_C(0x5349475245470003),82};return fwrite(h,sizeof h,1,stdout)!=1 || fwrite(v,8,82,stdout)!=82;
}
