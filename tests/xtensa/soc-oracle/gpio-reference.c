#include <stdint.h>
#include <stdio.h>
#include "pad-support.h"
#include "gpio_reg.h"
#include "gpio_struct.h"
#include "gpio_pins.h"
#include "interrupts.h"
#if S3
#include "system_reg.h"
#else
#include "dport_reg.h"
#endif
static uint64_t values[1024];static unsigned n;
static void v(uint64_t x){values[n++]=x;}
int main(void){
 v(S3?9:0);v(SOC_GPIO_PIN_COUNT);v(SOC_RTCIO_PIN_COUNT);v(SOC_GPIO_VALID_GPIO_MASK);v(SOC_GPIO_VALID_OUTPUT_GPIO_MASK);v(PIN_FUNC_GPIO);v(MCU_SEL_M);v(MCU_SEL_S);v(FUN_IE);
 v(RTC_GPIO_OUT_REG);v(RTC_GPIO_OUT_W1TS_REG);v(RTC_GPIO_OUT_W1TC_REG);v(RTC_GPIO_ENABLE_REG);v(RTC_GPIO_ENABLE_W1TS_REG);v(RTC_GPIO_ENABLE_W1TC_REG);v(RTC_GPIO_IN_REG);v(RTC_GPIO_OUT_DATA_S);v((uint32_t)RTC_GPIO_OUT_DATA_M);v(RTC_GPIO_PIN0_REG);v(RTC_GPIO_PIN0_PAD_DRIVER);
#if S3
 v(RTC_CNTL_PAD_HOLD_REG);v(RTC_CNTL_DIG_PAD_HOLD_REG);
#else
 v(RTC_CNTL_HOLD_FORCE_REG);v(RTC_IO_DIG_PAD_HOLD_REG);
#endif
 v(GPIO_MATRIX_CONST_ONE_INPUT);v(GPIO_MATRIX_CONST_ZERO_INPUT);v(GPIO_PCPU_INT_REG);v(GPIO_PCPU_INT1_REG);v(GPIO_PIN0_REG);v(GPIO_FUNC0_IN_SEL_CFG_REG);v(GPIO_FUNC0_OUT_SEL_CFG_REG);v(GPIO_STATUS_REG);v(GPIO_STATUS1_REG);v(GPIO_STATUS_W1TS_REG);v(GPIO_STATUS_W1TC_REG);
#if S3
 v(1u<<GPIO_PIN0_INT_ENA_S);
#else
 v(1u<<(GPIO_PIN0_INT_ENA_S+2));
#endif
 v(GPIO_OUT_REG);v(GPIO_OUT_W1TS_REG);v(GPIO_OUT_W1TC_REG);v(GPIO_ENABLE_REG);v(GPIO_ENABLE_W1TS_REG);v(GPIO_ENABLE_W1TC_REG);v(GPIO_OUT1_REG);v(GPIO_OUT1_W1TS_REG);v(GPIO_OUT1_W1TC_REG);v(GPIO_ENABLE1_REG);v(GPIO_ENABLE1_W1TS_REG);v(GPIO_ENABLE1_W1TC_REG);v(GPIO_IN_REG);v(GPIO_IN1_REG);v(GPIO_STATUS1_W1TS_REG);v(GPIO_STATUS1_W1TC_REG);v(GPIO_PIN0_PAD_DRIVER);v(GPIO_FUNC0_OUT_INV_SEL_M);v(GPIO_FUNC0_OEN_SEL_M);v(GPIO_FUNC0_OEN_INV_SEL_M);v(GPIO_FUNC0_IN_INV_SEL_M);v(GPIO_SIG0_IN_SEL_M);v(GPIO_PIN0_INT_TYPE_S);v(FUN_PU);v(FUN_PD);v(GPIO_PIN0_INT_ENA_M);v(GPIO_FUNC0_OUT_SEL_V);v(GPIO_FUNC0_IN_SEL_V);v(ETS_GPIO_INTR_SOURCE);
#if S3
 v(DR_REG_INTERRUPT_BASE);
#else
 v(DPORT_PRO_MAC_INTR_MAP_REG);
#endif
 v((uint32_t)GPIO_OUT1_DATA_M);v((uint32_t)GPIO_ENABLE1_DATA_M);v((uint32_t)GPIO_STATUS1_INT_M);
 v(sizeof(((gpio_dev_t*)0)->pin)/sizeof(((gpio_dev_t*)0)->pin[0]));v(sizeof(((gpio_dev_t*)0)->func_out_sel_cfg)/sizeof(((gpio_dev_t*)0)->func_out_sel_cfg[0]));
 unsigned globals=n;
 for(unsigned i=0;i<SOC_GPIO_PIN_COUNT;i++){
  uint64_t valid=GPIO_PIN_MUX_REG[i] && (SOC_GPIO_VALID_GPIO_MASK & (UINT64_C(1)<<i));int rt=rtc_io_num_map[i];const rtc_io_desc_t *p=rt<0?0:&rtc_io_desc[rt];
  v(GPIO_PIN_MUX_REG[i]);v(valid ? 1u | ((SOC_GPIO_VALID_OUTPUT_GPIO_MASK&(UINT64_C(1)<<i))?2u:0u):0u);v(p?(unsigned)rt+1:0);v(p?p->reg:0);v(p?p->mux:0);v(p?p->func:0);v(p?p->ie:0);v(p?p->pullup:0);v(p?p->pulldown:0);v(p?p->hold:0);v(p?p->hold_force:0);v(GPIO_HOLD_MASK[i]);v(p?p->slpie:0);v(p?p->slpoe:0);
 }
 uint64_t header[4]={UINT64_C(0x4750494f50414401),globals,SOC_GPIO_PIN_COUNT,14};return fwrite(header,sizeof header,1,stdout)!=1 || fwrite(values,8,n,stdout)!=n;
}
