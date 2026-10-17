/* Independent C callback ABI and PS oracle. No production scheduler logic. */
#include <stdint.h>
typedef uint32_t (*callback_t)(uint32_t,uint32_t,uint32_t,uint32_t,uint32_t,uint32_t,uint32_t,uint32_t);
volatile uint32_t masked_wait_peer[16];
uint32_t masked_wait_probe(uint32_t callback,uint32_t action,uint32_t expected) {
 uint32_t levels[3]={1,3,15};
 for(unsigned i=0;i<3;i++){
  uint32_t original,after,ps;__asm__ volatile("rsr.ps %0":"=a"(original));ps=(original&~15u)|levels[i];
  __asm__ volatile("wsr.ps %0\nrsync"::"a"(ps):"memory");
  uint32_t result=((callback_t)(uintptr_t)callback)(action,0,0,0,0,0,0,0);
  __asm__ volatile("rsr.ps %0":"=a"(after));
  __asm__ volatile("wsr.ps %0\nrsync"::"a"(original):"memory");
  masked_wait_peer[0]++;if(result!=expected)masked_wait_peer[1]|=1;if((after&15)!=levels[i])masked_wait_peer[1]|=2;
 }
 return masked_wait_peer[1];
}
uint32_t g_wifi_osi_funcs[121],g_wifi_default_wpa_crypto_funcs[13];
const char *WIFI_EVENT;uint32_t s_wifi_api_lock,g_wifi_global_lock,eloop_data_lock;
static uint32_t unexpected(void) {masked_wait_peer[2]++;return 999;}
#define STUB(name) uint32_t name(void){return unexpected();}
STUB(esp_wifi_stop) STUB(esp_wifi_start) STUB(esp_wifi_deinit_internal) STUB(esp_supplicant_deinit)
STUB(esp_wifi_init_internal) STUB(esp_wifi_set_storage) STUB(esp_wifi_set_mode) STUB(esp_supplicant_init)
STUB(esp_wifi_internal_reg_rxcb) STUB(esp_wifi_set_ps) STUB(esp_wifi_internal_free_rx_buffer)
STUB(phy_close_rf) STUB(phy_init_param_set) STUB(register_chipv7_phy) STUB(phy_wakeup_init) STUB(phy_wifi_enable_set) STUB(ets_delay_us)
STUB(btdm_controller_deinit) STUB(btdm_osi_funcs_register) STUB(btdm_lpclk_select_src) STUB(btdm_lpclk_set_div)
STUB(btdm_controller_set_sleep_mode) STUB(btdm_controller_init) STUB(btdm_rf_bb_init_phase2) STUB(coex_bt_high_prio)
STUB(btdm_controller_enable) STUB(API_vhci_host_register_callback) STUB(config_btdm_funcs_reset) STUB(config_ble_funcs_reset)
