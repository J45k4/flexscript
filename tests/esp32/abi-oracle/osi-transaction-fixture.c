#include <stdint.h>
#include "wifi_os_adapter.h"
struct transaction_guard {uint32_t before[4];wifi_osi_funcs_t table;uint32_t after[4];};
struct transaction_guard c_transaction_guard;
__asm__(".global g_wifi_osi_funcs\n.set g_wifi_osi_funcs,c_transaction_guard+16");
uint32_t c_transaction_reset(void) {
 for(unsigned i=0;i<4;i++){c_transaction_guard.before[i]=0x13572468+i;c_transaction_guard.after[i]=0x24681357+i;}
 for(unsigned i=0;i<sizeof(wifi_osi_funcs_t);i++)((volatile uint8_t *)&g_wifi_osi_funcs)[i]=0xa5;
 return 0;
}
uint32_t c_transaction_check(uint32_t ready) {
 for(unsigned i=0;i<4;i++)if(c_transaction_guard.before[i]!=0x13572468+i || c_transaction_guard.after[i]!=0x24681357+i)return 1;
 if(!ready)for(unsigned i=0;i<sizeof(wifi_osi_funcs_t);i++)if(((volatile uint8_t *)&g_wifi_osi_funcs)[i]!=0xa5)return 2;
 if(ready && (g_wifi_osi_funcs._version!=ESP_WIFI_OS_ADAPTER_VERSION || g_wifi_osi_funcs._magic!=ESP_WIFI_OS_ADAPTER_MAGIC))return 3;
 return 0;
}
