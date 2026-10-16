#include <stdint.h>
#include <stdio.h>
#include "rtc_cntl_reg.h"
#include "dport_reg.h"
#include "apb_ctrl_reg.h"
#include "regi2c_bbpll.h"
#include "pll-constants.h"
#define FIELD_MASK(msb,lsb) (((1u<<((msb)-(lsb)+1))-1)<<(lsb))
static const uint64_t values[]={
 RTC_CNTL_OPTIONS0_REG,RTC_CNTL_CLK_CONF_REG,RTC_CNTL_REG,RTC_CNTL_STORE4_REG,RTC_CNTL_STORE5_REG,APB_CTRL_SYSCLK_CONF_REG,DPORT_CPU_PER_CONF_REG,
 RTC_CNTL_SOC_CLK_SEL_M,RTC_CNTL_SOC_CLK_SEL_S,DPORT_CPUPERIOD_SEL_M,APB_CTRL_PRE_DIV_CNT_M,RTC_CNTL_DIG_DBIAS_WAK_M,RTC_CNTL_DIG_DBIAS_WAK_S,
 RTC_CNTL_BIAS_I2C_FORCE_PD|RTC_CNTL_BBPLL_FORCE_PD|RTC_CNTL_BBPLL_I2C_FORCE_PD|RTC_CNTL_BB_I2C_FORCE_PD,
 I2C_BBPLL,I2C_BBPLL_HOSTID,CLK_LL_BBPLL_IR_CAL_DELAY_VAL,CLK_LL_BBPLL_IR_CAL_EXT_CAP_VAL,CLK_LL_BBPLL_OC_ENB_FCAL_VAL,CLK_LL_BBPLL_OC_ENB_VCON_VAL,CLK_LL_BBPLL_BBADC_CAL_7_0_VAL,
 CLK_LL_BBPLL_ENDIV5_VAL_320M,CLK_LL_BBPLL_BBADC_DSMP_VAL_320M,CLK_LL_BBPLL_ENDIV5_VAL_480M,CLK_LL_BBPLL_BBADC_DSMP_VAL_480M,
 I2C_BBPLL_OC_LREF,I2C_BBPLL_OC_DIV_7_0,I2C_BBPLL_OC_DCUR,I2C_BBPLL_ENDIV5,I2C_BBPLL_BBADC_DSMP,DR_REG_ANA_BASE,
 DR_REG_ANA_BASE-DR_REG_DPORT_APB_BASE+0x60000000u,
 I2C_BBPLL_IR_CAL_DELAY,I2C_BBPLL_IR_CAL_EXT_CAP,I2C_BBPLL_OC_ENB_FCAL,I2C_BBPLL_OC_ENB_VCON,I2C_BBPLL_BBADC_CAL_7_0,
 FIELD_MASK(I2C_BBPLL_OC_REF_DIV_MSB,I2C_BBPLL_OC_REF_DIV_LSB),FIELD_MASK(I2C_BBPLL_OC_DIV_10_8_MSB,I2C_BBPLL_OC_DIV_10_8_LSB),1u<<I2C_BBPLL_OC_LREF_LSB,
 /* The following two40MHz-XTAL divider values are the SDK switch cases in
    clk_ll_bbpll_set_config, not generated from the emulator/firmware driver. */
 32,28,(3u<<I2C_BBPLL_OC_BW_LSB)|6u,
 /* Controller command/busy bits independently observed in the ROM's
    rom_chip_i2c_readReg/writeReg instructions; not SDK C declarations. */
 1u<<24,1u<<25
};
static void word(uint64_t v){fwrite(&v,sizeof(v),1,stdout);}
int main(void){word(UINT64_C(0x455350434c4b0001));word(sizeof(values)/sizeof(values[0]));fwrite(values,sizeof(values),1,stdout);word(1027);
 for(unsigned d=1;d<=1024;d++){word(0);word(d);word(0);word(40000000u/d);word(40000000u/d);}
 for(unsigned p=0;p<3;p++){word(p==2?480:320);word(1);word(p);word(80000000u*(p+1));word(80000000);}
 return ferror(stdout)?1:0;}
