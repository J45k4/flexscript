#include <stdio.h>
#include <stdint.h>
#define __ASSEMBLER__ 1
#include "soc/syscon_reg.h"
#include "soc/efuse_reg.h"
#include "soc/rtc_cntl_reg.h"
#include "wdev_reg.h"
// Init mask/clear bits: pinned esp-hal S3 radio clock initialization.
int main(void){const uint64_t data[]={SYSTEM_WIFI_CLK_EN_REG,SYSTEM_WIFI_RST_EN_REG,SYSTEM_WIFI_CLK_WIFI_BT_COMMON_M,SYSTEM_WIFIMAC_RST,WDEV_RND_REG,EFUSE_RD_MAC_SPI_SYS_0_REG,EFUSE_RD_MAC_SPI_SYS_1_REG,RTC_CNTL_STORE1_REG,0x00fb9fcf,(1U<<5)|(1U<<12)|(1U<<13)};return fwrite(data,sizeof(data),1,stdout)!=1;}
