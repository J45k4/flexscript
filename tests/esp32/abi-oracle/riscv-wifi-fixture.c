/* C3/C6 station ABI peer; real native OSI callbacks, synthetic vendor lifecycle. No RF. */
#include <stdbool.h>
#include <stddef.h>
#include "wifi_os_adapter.h"
#include "esp_wifi.h"
_Static_assert(sizeof(wifi_init_config_t)==160,"init ABI");
_Static_assert(sizeof(wifi_sta_config_t)==184,"station ABI");
#include <stdint.h>
#include <math.h>
typedef uint32_t (*callback_t)(uint32_t,uint32_t,uint32_t,uint32_t,uint32_t,uint32_t,uint32_t,uint32_t);
wifi_osi_funcs_t g_wifi_osi_funcs;
const wpa_crypto_funcs_t g_wifi_default_wpa_crypto_funcs={.size=52,.version=0x12345678,
.hmac_sha256_vector=(__typeof__(g_wifi_default_wpa_crypto_funcs.hmac_sha256_vector))0x11223344,
.pbkdf2_sha1=(__typeof__(g_wifi_default_wpa_crypto_funcs.pbkdf2_sha1))0x12233445,
.aes_128_encrypt=(__typeof__(g_wifi_default_wpa_crypto_funcs.aes_128_encrypt))0x13243546,
.aes_128_decrypt=(__typeof__(g_wifi_default_wpa_crypto_funcs.aes_128_decrypt))0x14253647,
.omac1_aes_128=(__typeof__(g_wifi_default_wpa_crypto_funcs.omac1_aes_128))0x15263748,
.ccmp_decrypt=(__typeof__(g_wifi_default_wpa_crypto_funcs.ccmp_decrypt))0x16273849,
.ccmp_encrypt=(__typeof__(g_wifi_default_wpa_crypto_funcs.ccmp_encrypt))0x1728394a,
.aes_gmac=(__typeof__(g_wifi_default_wpa_crypto_funcs.aes_gmac))0x18293a4b,
.sha256_vector=(__typeof__(g_wifi_default_wpa_crypto_funcs.sha256_vector))0x192a3b4c,
.aes_wrap=(__typeof__(g_wifi_default_wpa_crypto_funcs.aes_wrap))0x1a2b3c4d,
.aes_unwrap=(__typeof__(g_wifi_default_wpa_crypto_funcs.aes_unwrap))0x1b2c3d4e};
__asm__(".pushsection .data\n.global WIFI_EVENT\n.type WIFI_EVENT,@object\n.size WIFI_EVENT,4\nWIFI_EVENT: .word 0\n.popsection");
uint32_t s_wifi_api_lock,eloop_data_lock;
volatile uint32_t wifi_lifecycle_oracle[32];
static int step(unsigned n) {uint32_t ps;__asm__ volatile("csrr %0, mstatus":"=r"(ps));if(!(ps&8))return 995;wifi_lifecycle_oracle[n+8]++;return (wifi_lifecycle_oracle[0]==n||wifi_lifecycle_oracle[1]==n)?(int)(700+n):0;}
static void irq(void *p) {(void)p;}
static void worker(void *p) {(void)p;}
static uint32_t task;static callback_t rx_callback;
_Static_assert(offsetof(wifi_event_sta_connected_t,bssid)==33 && offsetof(wifi_event_sta_connected_t,channel)==39,"connected event ABI");
_Static_assert(offsetof(wifi_event_sta_disconnected_t,reason)==39,"disconnected event ABI");
extern volatile uint64_t esp_radio_hw_ready;
void ets_delay_us(uint32_t n) {if(n!=10)wifi_lifecycle_oracle[28]++;wifi_lifecycle_oracle[29]++;}
void phy_init_param_set(int n) {(void)n;}
int register_chipv7_phy(void *a,void *b,int c) {(void)a;(void)b;(void)c;return 0;}
void phy_wakeup_init(void) {}
void phy_wifi_enable_set(int n) {(void)n;}
void phy_close_rf(void) {}
uint32_t s3_wifi_check_init(const wifi_init_config_t *cfg,uint32_t osi,int nvs) {
 wifi_init_config_t expected;for(unsigned i=0;i<sizeof(expected);i++)((uint8_t *)&expected)[i]=0;
 expected.osi_funcs=(wifi_osi_funcs_t *)(uintptr_t)osi;expected.wpa_crypto_funcs=g_wifi_default_wpa_crypto_funcs;
 expected.static_rx_buf_num=4;expected.dynamic_rx_buf_num=8;expected.tx_buf_type=1;expected.dynamic_tx_buf_num=8;
 expected.rx_mgmt_buf_num=5;expected.rx_ba_win=6;expected.beacon_max_len=752;expected.mgmt_sbuf_num=6;
 expected.nvs_enable=nvs;expected.tx_hetb_queue_num=3;expected.magic=WIFI_INIT_CONFIG_MAGIC;
 for(unsigned i=0;i<sizeof(expected);i++)if(((const uint8_t *)cfg)[i]!=((uint8_t *)&expected)[i])return 960+i;
 return 0;
}
int esp_wifi_init_internal(const wifi_init_config_t *cfg) {
 int r=step(1);if(r)return r;if(!esp_radio_hw_ready)return 994;
 r=s3_wifi_check_init(cfg,(uint32_t)(uintptr_t)&g_wifi_osi_funcs,0);if(r)return r;
 wifi_lifecycle_oracle[30]++;

 if(!s_wifi_api_lock)s_wifi_api_lock=(uint32_t)(uintptr_t)g_wifi_osi_funcs._recursive_mutex_create();
 if(!eloop_data_lock)eloop_data_lock=(uint32_t)(uintptr_t)g_wifi_osi_funcs._mutex_create();
 uint32_t *locks[2]={(uint32_t *)(uintptr_t)s_wifi_api_lock,(uint32_t *)(uintptr_t)eloop_data_lock};
 for(unsigned i=0;i<2;i++)if(!locks[i] || locks[i][-1]!=0x48454150 || (locks[i][-4]&15)!=3)return 996;
 if(!g_wifi_osi_funcs._semphr_create(1,0)||!g_wifi_osi_funcs._wifi_thread_semphr_get())return 999;
 g_wifi_osi_funcs._set_isr(0,(void *)irq,0);
 if(!g_wifi_osi_funcs._task_create_pinned_to_core((void *)worker,0,4096,0,3,&task,0))return 997;
 return 0;
}
int esp_wifi_set_storage(wifi_storage_t n) {(void)n;return step(2);}
int esp_wifi_set_mode(wifi_mode_t n) {(void)n;return step(3);}
int esp_supplicant_init(void) {return step(4);}
int esp_wifi_internal_reg_rxcb(int n,void *p) {int r=step(5);if(!r){if(n)return 993;rx_callback=(callback_t)p;}return r;}
int esp_wifi_start(void) {int r=step(6);if(!r)g_wifi_osi_funcs._event_post(WIFI_EVENT,2,0,0,0);return r;}
int esp_wifi_set_ps(wifi_ps_type_t n) {(void)n;return step(7);}
int esp_wifi_stop(void) {int r=step(8);if(!r)g_wifi_osi_funcs._event_post(WIFI_EVENT,3,0,0,0);return r;}
int esp_wifi_deinit_internal(void) {int r=step(9);if(!r && task){g_wifi_osi_funcs._task_delete((void *)(uintptr_t)task);task=0;}return r;}
int esp_supplicant_deinit(void) {return step(10);}
void esp_wifi_internal_free_rx_buffer(void *p) {wifi_lifecycle_oracle[26]++;if((uintptr_t)p!=0x55)wifi_lifecycle_oracle[27]++;}

void btdm_controller_deinit(void) {wifi_lifecycle_oracle[31]++;}

void phy_bbpll_en_usb(int n) {(void)n;}
void phy_dig_reg_backup(int save,void *data){(void)save;(void)data;}
void phy_xpd_tsens(void) {}

/* GNU aggregate initialization support in this independent test peer. */
void *memset(void *dest,int value,size_t size) {volatile uint8_t *p=dest;for(size_t i=0;i<size;i++)p[i]=(uint8_t)value;return dest;}

uint32_t s3_wifi_check_station(const wifi_sta_config_t *cfg,int auth) {
 wifi_sta_config_t expected;volatile uint8_t *p=(volatile uint8_t *)&expected;
 for(unsigned i=0;i<sizeof(expected);i++)p[i]=0;
 const char *ssid="testssid",*password="testpassword";
 for(unsigned i=0;i<8;i++)expected.ssid[i]=ssid[i];
 for(unsigned i=0;i<12;i++)expected.password[i]=password[i];
 expected.scan_method=WIFI_ALL_CHANNEL_SCAN;expected.threshold.rssi=-99;
 expected.threshold.authmode=(wifi_auth_mode_t)auth;expected.pmf_cfg.capable=1;
 expected.pmf_cfg.required=auth==WIFI_AUTH_WPA3_PSK;expected.sae_pwe_h2e=WPA3_SAE_PWE_BOTH;
 for(unsigned i=0;i<sizeof(expected);i++)if(((const uint8_t *)cfg)[i]!=p[i])return i+1;
 return 0;
}

void *memcpy(void *dest,const void *src,size_t size) {volatile uint8_t *d=dest;const volatile uint8_t *s=src;for(size_t i=0;i<size;i++)d[i]=s[i];return dest;}

int esp_wifi_connect_internal(void){int r=step(11);if(!r){wifi_event_sta_connected_t event={0};for(unsigned i=0;i<6;i++)event.bssid[i]=0xa1+i;event.channel=6;g_wifi_osi_funcs._event_post(WIFI_EVENT,4,&event,sizeof(event),0);}return r;}
int esp_wifi_disconnect_internal(void){return step(12);}
int esp_wifi_set_config(wifi_interface_t iface,wifi_config_t *config){int r=step(13);if(!r){if(iface!=WIFI_IF_STA || s3_wifi_check_station(&config->sta,3))return 992;wifi_lifecycle_oracle[25]=(uint32_t)(uintptr_t)config;}return r;}
int esp_wifi_internal_tx(int iface,void *buffer,int size){int r=step(14);if(!r){if(iface||size!=14)return 991;for(unsigned i=0;i<14;i++)if(((uint8_t *)buffer)[i]!=i+1)return 990;wifi_lifecycle_oracle[24]++;}return r;}

uint32_t c_wifi_deliver_frame(void){if(!rx_callback)return 1;uint8_t packet[14];for(unsigned i=0;i<14;i++)packet[i]=i+1;rx_callback((uint32_t)(uintptr_t)packet,14,0x55,0,0,0,0,0);return 0;}
uint32_t c_wifi_credentials_cleared(void){const uint8_t *p=(const uint8_t *)(uintptr_t)wifi_lifecycle_oracle[25];if(!p)return 1;for(unsigned i=32;i<96;i++)if(p[i])return 2;return 0;}

/* Execute the exact newlib soft-double dependency used by C6 HE code on C3.
 * Integer bit vectors prevent constant-folded calls from hiding ABI mistakes. */
uint32_t c_wifi_math_probe(void){
 static const uint64_t vectors[][2]={
  {0x3ffc000000000000ULL,0x3ff0000000000000ULL}, /* 1.75 -> 1 */
  {0xbffc000000000000ULL,0xc000000000000000ULL}, /* -1.75 -> -2 */
  {0,0},{0x8000000000000000ULL,0x8000000000000000ULL},
  {1,0},{0x8000000000000001ULL,0xbff0000000000000ULL},
  {0x4330000000000000ULL,0x4330000000000000ULL},
  {0x7ff0000000000000ULL,0x7ff0000000000000ULL},
  {0xfff0000000000000ULL,0xfff0000000000000ULL}
 };
 for(unsigned i=0;i<sizeof(vectors)/sizeof(vectors[0]);i++){
  union{double d;uint64_t u;}in,out;in.u=vectors[i][0];out.d=floor(in.d);
  if(out.u!=vectors[i][1])return i+1;
 }
 return 0;
}
