#include <stdio.h>
#include <stdint.h>
#define __ASSEMBLER__ 1
#include "soc/syscon_reg.h"
#include "soc/rtc_cntl_reg.h"
/* Registers and reset fields come from pinned vendor headers. Clock setup and
 * delay follow the matching pinned esp-hal radio/common_adapter sources. */
int main(void) {
 const uint64_t values[]={SYSTEM_WIFI_CLK_EN_REG,RTC_CNTL_DIG_PWC_REG,
 RTC_CNTL_DIG_ISO_REG,SYSTEM_WIFI_RST_EN_REG,RTC_CNTL_WIFI_FORCE_PD,
 RTC_CNTL_WIFI_FORCE_ISO,SYSTEM_WIFIBB_RST|SYSTEM_FE_RST|SYSTEM_WIFIMAC_RST|
 SYSTEM_BTBB_RST|SYSTEM_BTMAC_RST|SYSTEM_RW_BTMAC_RST|SYSTEM_RW_BTMAC_REG_RST|
 SYSTEM_BTBB_REG_RST,0x00fb9fcf,(1U<<5)|(1U<<12)|(1U<<13),10};
 return fwrite(values,sizeof(values),1,stdout)!=1;
}
