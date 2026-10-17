#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include "rmt_struct.h"
#include "rmt_reg.h"
#include "gpio_reg.h"
#include "io_mux_reg.h"
#include "gpio_sig_map.h"
#include "interrupts.h"
#include "dport_reg.h"
static uint64_t a[96];static unsigned n;
static void v(uint64_t x){a[n++]=x;}
int main(void){
 v(DR_REG_RMT_BASE);v(RMT_CHANNEL_MEM(0));v(DPORT_PERIP_CLK_EN_REG);v(DPORT_PERIP_RST_EN_REG);v(DPORT_RMT_CLK_EN);v(DPORT_RMT_RST);
 v(offsetof(rmt_dev_t,conf_ch));v(sizeof(((rmt_dev_t*)0)->conf_ch[0]));v(offsetof(rmt_dev_t,status_ch));v(offsetof(rmt_dev_t,int_raw));v(offsetof(rmt_dev_t,int_st));v(offsetof(rmt_dev_t,int_ena));v(offsetof(rmt_dev_t,int_clr));v(offsetof(rmt_dev_t,apb_conf));v(offsetof(rmt_dev_t,tx_lim_ch));v(offsetof(rmt_dev_t,carrier_duty_ch));
 rmt_dev_t reset={0};reset.conf_ch[0].conf0.div_cnt=2;reset.conf_ch[0].conf0.idle_thres=0x1000;reset.conf_ch[0].conf0.mem_size=1;reset.conf_ch[0].conf0.carrier_en=1;reset.conf_ch[0].conf0.carrier_out_lv=1;reset.conf_ch[0].conf1.mem_owner=1;reset.conf_ch[0].conf1.rx_filter_thres=15;v(reset.conf_ch[0].conf0.val);v(reset.conf_ch[0].conf1.val);
 v(RMT_CLK_EN);v(RMT_MEM_PD);v(RMT_REF_ALWAYS_ON_CH0);v(RMT_MEM_OWNER_CH0);v(RMT_RX_EN_CH0);v(RMT_TX_START_CH0);v(RMT_MEM_WR_RST_CH0);v(RMT_MEM_RD_RST_CH0);v(RMT_APB_MEM_RST_CH0);v(RMT_REF_CNT_RST_CH0);v(RMT_IDLE_OUT_EN_CH0);v(RMT_IDLE_OUT_LV_CH0);v(RMT_RX_FILTER_EN_CH0);v(RMT_RX_FILTER_THRES_CH0_M);v(RMT_APB_FIFO_MASK);v(RMT_MEM_TX_WRAP_EN);v(RMT_CARRIER_EN_CH0);v(RMT_TX_CONTI_MODE_CH0);v(RMT_SIG_IN0_IDX);v(RMT_SIG_OUT0_IDX);v(ETS_RMT_INTR_SOURCE);v(GPIO_FUNC0_OUT_SEL_CFG_REG);v(GPIO_FUNC0_IN_SEL_CFG_REG);v(IO_MUX_GPIO21_REG);v(IO_MUX_GPIO19_REG);v(IO_MUX_GPIO18_REG);v(IO_MUX_GPIO25_REG);v(GPIO_ENABLE_W1TS_REG);v((2u<<MCU_SEL_S)|FUN_IE);v(DPORT_PRO_MAC_INTR_MAP_REG);v(GPIO_OUT_W1TS_REG);v(GPIO_OUT_W1TC_REG);v(GPIO_ENABLE_W1TC_REG);
 v(RMT_MEM_SIZE_CH0_S);v(RMT_MEM_OWNER_ERR_CH0);v(RMT_MEM_FULL_CH0);v(RMT_MEM_EMPTY_CH0);v(RMT_MEM_WADDR_EX_CH0_M);v(RMT_MEM_RADDR_EX_CH0_M);v(RMT_MEM_RADDR_EX_CH0_S);v(RMT_STATE_CH0_M);v(RMT_STATE_CH0_S);v(RMT_DIV_CNT_CH0_M);v(RMT_IDLE_THRES_CH0_S);v(RMT_IDLE_THRES_CH0_V);v(RMT_RX_FILTER_THRES_CH0_S);
 for(unsigned b=1;b<=8;b++){rmt_dev_t h={0};h.conf_ch[0].conf0.mem_size=b;v(h.conf_ch[0].conf0.val);}
 uint64_t header[4]={UINT64_C(0x524d544d4f440001),n,0,0};if(fwrite(header,sizeof header,1,stdout)!=1 || fwrite(a,8,n,stdout)!=n)return 1;return 0;
}
