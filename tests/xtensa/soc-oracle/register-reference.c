#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include "uart_struct.h"
#include "uart_reg.h"
#include "gpio_reg.h"
#include "io_mux_reg.h"
#include "timer_group_struct.h"
#include "timer_group_reg.h"
#include "interrupts.h"
#if S3
#include "system_reg.h"
#else
#include "dport_reg.h"
#endif
static uint64_t a[128];static unsigned n;
static void v(uint64_t x){a[n++]=x;}
int main(void){
 v(S3?9:0);v(DR_REG_UART_BASE);v(DR_REG_UART1_BASE);v(DR_REG_UART2_BASE);
 v(offsetof(uart_dev_t,fifo));v(offsetof(uart_dev_t,status));v(offsetof(uart_dev_t,conf0));v(offsetof(uart_dev_t,conf1));v(offsetof(uart_dev_t,int_ena));v(offsetof(uart_dev_t,int_raw));v(offsetof(uart_dev_t,int_clr));
#if S3
 v(offsetof(uart_dev_t,clkdiv));
#else
 v(offsetof(uart_dev_t,clk_div));
#endif

 v(UART_RXFIFO_CNT_M);v(UART_TXFIFO_CNT_S);v(UART_RXFIFO_RST);v(UART_TXFIFO_RST);
 v(DR_REG_GPIO_BASE);v(GPIO_OUT_REG);v(GPIO_OUT_W1TS_REG);v(GPIO_OUT_W1TC_REG);v(GPIO_OUT1_REG);v(GPIO_OUT1_W1TS_REG);v(GPIO_OUT1_W1TC_REG);v(GPIO_ENABLE_REG);v(GPIO_ENABLE_W1TS_REG);v(GPIO_ENABLE_W1TC_REG);v(GPIO_ENABLE1_REG);v(GPIO_ENABLE1_W1TS_REG);v(GPIO_ENABLE1_W1TC_REG);v(GPIO_IN_REG);v(GPIO_IN1_REG);v(GPIO_STATUS_REG);v(GPIO_STATUS1_REG);v(GPIO_STATUS_W1TC_REG);v(GPIO_STATUS1_W1TC_REG);v(GPIO_PIN0_REG);v(GPIO_FUNC0_IN_SEL_CFG_REG);v(GPIO_FUNC0_OUT_SEL_CFG_REG);v(FUN_PU);v(FUN_PD);
 v(DR_REG_TIMERGROUP0_BASE);v(DR_REG_TIMERGROUP1_BASE);v(sizeof(timg_hwtimer_reg_t));v(offsetof(timg_hwtimer_reg_t,lo));v(offsetof(timg_hwtimer_reg_t,hi));v(offsetof(timg_hwtimer_reg_t,update));v(offsetof(timg_hwtimer_reg_t,alarmlo));v(offsetof(timg_hwtimer_reg_t,alarmhi));v(offsetof(timg_hwtimer_reg_t,loadlo));v(offsetof(timg_hwtimer_reg_t,loadhi));v(offsetof(timg_hwtimer_reg_t,load));
 v(offsetof(timg_dev_t,int_ena_timers));v(offsetof(timg_dev_t,int_raw_timers));v(offsetof(timg_dev_t,int_st_timers));v(offsetof(timg_dev_t,int_clr_timers));v(TIMG_T0_ALARM_EN);v(TIMG_T0_INCREASE);v(TIMG_T0_EN);v(TIMG_T0_AUTORELOAD);v(TIMG_T0_DIVIDER_M);v(TIMG_T0_HI_M);
#if S3
 v(SYSTEM_PERIP_CLK_EN0_REG);v(SYSTEM_PERIP_RST_EN0_REG);v(SYSTEM_UART_CLK_EN);v(SYSTEM_UART1_CLK_EN);v(SYSTEM_UART2_CLK_EN);v(SYSTEM_TIMERGROUP_CLK_EN);v(SYSTEM_TIMERGROUP1_CLK_EN);v(DR_REG_INTERRUPT_BASE);v(1u<<GPIO_PIN0_INT_ENA_S);v(TIMG_T0_USE_XTAL);
#else
 v(DPORT_PERIP_CLK_EN_REG);v(DPORT_PERIP_RST_EN_REG);v(DPORT_UART_CLK_EN);v(DPORT_UART1_CLK_EN);v(DPORT_UART2_CLK_EN);v(DPORT_TIMERGROUP_CLK_EN);v(DPORT_TIMERGROUP1_CLK_EN);v(DPORT_PRO_MAC_INTR_MAP_REG);v(1u<<(GPIO_PIN0_INT_ENA_S+2));v(TIMG_T0_LEVEL_INT_EN);
#endif
 v(ETS_GPIO_INTR_SOURCE);v(ETS_UART0_INTR_SOURCE);v(ETS_UART1_INTR_SOURCE);v(ETS_UART2_INTR_SOURCE);v(ETS_TG0_T0_LEVEL_INTR_SOURCE);v(ETS_TG0_T1_LEVEL_INTR_SOURCE);v(ETS_TG1_T0_LEVEL_INTR_SOURCE);v(ETS_TG1_T1_LEVEL_INTR_SOURCE);
 v(IO_MUX_GPIO4_REG);v(IO_MUX_GPIO19_REG);v(IO_MUX_GPIO21_REG);v(IO_MUX_GPIO33_REG);
 v(UART_RXFIFO_FULL_THRHD_M);v(UART_TXFIFO_EMPTY_THRHD_S);v(UART_TXFIFO_EMPTY_THRHD_M);

#if S3
 v(offsetof(uart_dev_t,fsm_status));
#else
 v(offsetof(uart_dev_t,status));
#endif
 v(UART_ST_UTX_OUT_S);v(UART_ST_UTX_OUT_M);v(UART_TX_DONE_INT_RAW);v(offsetof(uart_dev_t,idle_conf));v(UART_TX_IDLE_NUM_S);v(UART_TX_IDLE_NUM_M);v(UART_LOOPBACK);v(UART_CLKDIV_M);v(UART_CLKDIV_FRAG_M);
#if S3
 v(UART_SCLK_SEL_M);v(offsetof(uart_dev_t,clk_conf));v(UART_SCLK_EN|UART_TX_SCLK_EN|UART_RX_SCLK_EN);v(UART_SCLK_DIV_NUM_S);
#else
 v(UART_TICK_REF_ALWAYS_ON);v(0);v(0);v(0);
#endif
 v(UART_TXD_M);v(UART_TXFIFO_CNT_M);
 uint64_t h[2]={UINT64_C(0x455350534f430001),n};return fwrite(h,sizeof h,1,stdout)!=1 || fwrite(a,8,n,stdout)!=n;
}
