// Compile against each chip's unmodified ESP-IDF v5.5.1 headers.
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include "soc_caps.h"
#include "timer_group_reg.h"
#include "timer_group_struct.h"
static uint64_t meta[32];static unsigned n;
static void v(uint64_t x){meta[n++]=x;}
int main(void){
 v(UINT64_C(0x54494d4552570001));v(SOC_TIMER_GROUP_COUNTER_BIT_WIDTH);
 v(DR_REG_TIMERGROUP0_BASE);v(DR_REG_TIMERGROUP1_BASE);v(sizeof(timg_hwtimer_reg_t));
 v(offsetof(timg_hwtimer_reg_t,lo));v(offsetof(timg_hwtimer_reg_t,hi));v(offsetof(timg_hwtimer_reg_t,update));
 v(offsetof(timg_hwtimer_reg_t,loadlo));v(offsetof(timg_hwtimer_reg_t,loadhi));v(offsetof(timg_hwtimer_reg_t,load));
 v(offsetof(timg_hwtimer_reg_t,alarmlo));v(offsetof(timg_hwtimer_reg_t,alarmhi));
 v(offsetof(timg_dev_t,int_ena_timers));v(TIMG_T0_HI_M);v(TIMG_T0_LOAD_HI_M);v(TIMG_T0_ALARM_HI_M);
 v(TIMG_T0_ALARM_EN);v(TIMG_T0_AUTORELOAD);v(TIMG_T0_EN);v(TIMG_T0_INCREASE);
 uint32_t values[40]={0,UINT32_MAX,0x7fffffff,0x003fffff,0x00400000,0xffffffea,0xffffff92,0x89abcdef};
 for(unsigned i=0;i<32;i++)values[8+i]=UINT32_C(1)<<i;
 v(40*40);v(n+1);
 if(fwrite(meta,8,n,stdout)!=n)return 1;
 for(unsigned a=0;a<40;a++)for(unsigned b=0;b<40;b++){
  uint64_t x=((uint64_t)values[b]<<32)|values[a];
  uint64_t max=SOC_TIMER_GROUP_COUNTER_BIT_WIDTH==64?UINT64_MAX:((UINT64_C(1)<<54)-1);
  uint32_t row[]={values[a],values[b],x<=max,x<=max && x<=INT64_MAX,x<=max && x<=INT64_MAX && x!=0};
  if(fwrite(row,sizeof row,1,stdout)!=1)return 1;
 }
 return 0;
}
