#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include "sens_struct.h"
#include "sens_reg.h"
#include "rtc_io_struct.h"
#include "rtc_io_reg.h"
#include "rtc_cntl_reg.h"
#include "syscon_struct.h"
#include "syscon_reg.h"
#include "adc_channel.h"
#include "rtc_io_channel.h"
#include "io_mux_reg.h"
#include "gpio_reg.h"
#include "rtc-descriptors.h"
#include "gpio-mux.h"
static uint64_t values[320];static unsigned n;
static void v(uint64_t value){values[n++]=value;}
int main(void){
 sens_dev_t s={0};syscon_dev_t y={0};
 v(DR_REG_SENS_BASE);v(offsetof(sens_dev_t,sar_read_ctrl));v(offsetof(sens_dev_t,sar_read_ctrl2));v(offsetof(sens_dev_t,sar_start_force));v(offsetof(sens_dev_t,sar_meas_start1));v(offsetof(sens_dev_t,sar_meas_start2));v(offsetof(sens_dev_t,sar_meas_wait1));v(offsetof(sens_dev_t,sar_meas_wait2));v(offsetof(sens_dev_t,sar_meas_ctrl));v(offsetof(sens_dev_t,sar_slave_addr1));v(offsetof(sens_dev_t,sar_atten1));v(offsetof(sens_dev_t,sar_atten2));v(offsetof(sens_dev_t,sar_touch_ctrl1));v(offsetof(sens_dev_t,sar_meas_ctrl2));v(DR_REG_RTCIO_BASE);v(offsetof(rtc_io_dev_t,hall_sens));v(DR_REG_SYSCON_BASE);v(offsetof(syscon_dev_t,saradc_ctrl));y.saradc_ctrl.sar2_mux=1;v(y.saradc_ctrl.val);
 v(SENS_SAR1_SAMPLE_BIT_M);v(SENS_SAR1_DIG_FORCE);v(SENS_SAR1_DATA_INV);v(SENS_SAR2_DIG_FORCE);v(SENS_SAR2_PWDET_FORCE);v(SENS_SAR2_DATA_INV);v(SENS_SAR1_BIT_WIDTH_M);v(SENS_SAR2_BIT_WIDTH_M);v(SENS_SAR1_STOP);v(SENS_SAR2_STOP);v(SENS_SAR2_PWDET_CCT_M);
 s.sar_meas_wait2.force_xpd_sar=3;v(s.sar_meas_wait2.val);v(SENS_FORCE_XPD_SAR_M);s.sar_meas_wait2.val=0;s.sar_meas_wait2.force_xpd_amp=SENS_FORCE_XPD_AMP_PD;v(s.sar_meas_wait2.val);v(SENS_FORCE_XPD_AMP_M);s.sar_meas_wait1.sar_amp_wait1=1;s.sar_meas_wait1.sar_amp_wait2=1;v(s.sar_meas_wait1.val);v(SENS_AMP_RST_FB_FSM_M|SENS_AMP_SHORT_REF_FSM_M|SENS_AMP_SHORT_REF_GND_FSM_M);v(SENS_XPD_HALL_FORCE|SENS_HALL_PHASE_FORCE);v(RTC_IO_XPD_HALL);v(SENS_SAR1_DAC_XPD_FSM_M);
 v(SENS_MEAS1_START_SAR);v(SENS_MEAS1_DONE_SAR);v(SENS_MEAS1_START_FORCE);v(SENS_SAR1_EN_PAD_FORCE);v(SENS_SAR1_EN_PAD_M);v(SENS_MEAS_STATUS_M);v(SENS_SAR1_CLK_DIV_M);v(SENS_MEAS1_DATA_SAR_M);v(FUN_IE);v(RTC_GPIO_ENABLE_W1TC_REG);v(GPIO_ENABLE_W1TC_REG);v(GPIO_ENABLE1_W1TC_REG);v(RTC_GPIO_ENABLE_W1TC_S);v(RTC_CNTL_HOLD_FORCE_REG);v(RTC_IO_XPD_XTAL_32K);
 const int pins[18]={ADC1_CHANNEL_0_GPIO_NUM,ADC1_CHANNEL_1_GPIO_NUM,ADC1_CHANNEL_2_GPIO_NUM,ADC1_CHANNEL_3_GPIO_NUM,ADC1_CHANNEL_4_GPIO_NUM,ADC1_CHANNEL_5_GPIO_NUM,ADC1_CHANNEL_6_GPIO_NUM,ADC1_CHANNEL_7_GPIO_NUM,ADC2_CHANNEL_0_GPIO_NUM,ADC2_CHANNEL_1_GPIO_NUM,ADC2_CHANNEL_2_GPIO_NUM,ADC2_CHANNEL_3_GPIO_NUM,ADC2_CHANNEL_4_GPIO_NUM,ADC2_CHANNEL_5_GPIO_NUM,ADC2_CHANNEL_6_GPIO_NUM,ADC2_CHANNEL_7_GPIO_NUM,ADC2_CHANNEL_8_GPIO_NUM,ADC2_CHANNEL_9_GPIO_NUM};
 for(unsigned i=0;i<18;i++){int pin=pins[i],rt=rtc_io_num_map[pin];const rtc_io_desc_t *p=&rtc_io_desc[rt];v(pin);v(rt);v(p->reg);v(p->mux);v(3u<<p->func);v(p->ie);v(p->pullup|p->pulldown);v(p->slpsel);v(p->hold);v(p->hold_force);v(pin==25||pin==26 ? RTC_IO_PDAC1_XPD_DAC|RTC_IO_PDAC1_DAC_XPD_FORCE : 0);v(pin==25||pin==26 ? RTC_IO_PDAC1_DAC_XPD_FORCE : 0);v(GPIO_PIN_MUX_REG[pin]);}
 uint64_t header[2]={UINT64_C(0x4144435245470001),n};return fwrite(header,sizeof header,1,stdout)!=1 || fwrite(values,8,n,stdout)!=n;
}
