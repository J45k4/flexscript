/* Independent C packet/lifecycle peer. All busy frames omit scheduler calls. */
#include <stdint.h>
typedef uint32_t (*callback_t)(uint32_t,uint32_t,uint32_t,uint32_t,uint32_t,uint32_t,uint32_t,uint32_t);
volatile uint32_t wifi_packet_peer[32];
uint32_t g_wifi_osi_funcs[121],g_wifi_default_wpa_crypto_funcs[13];
const char *WIFI_EVENT;
uint32_t s_wifi_api_lock,g_wifi_global_lock,eloop_data_lock;
extern volatile uint64_t esp_wifi_tx_active,esp_wifi_rx_callbacks;
static void unmasked(void) {uint32_t ps;__asm__ volatile("rsr.ps %0":"=a"(ps));if(ps&15)wifi_packet_peer[2]|=1;}
static void phase(unsigned kind,unsigned flag) {
 uint32_t begin,now;wifi_packet_peer[24]=kind;__asm__ volatile("rsr.ccount %0":"=a"(begin));
 do{if(wifi_packet_peer[flag])return;__asm__ volatile("rsr.ccount %0":"=a"(now));}while((uint32_t)(now-begin)<8000000);
 wifi_packet_peer[2]|=32;
}
int esp_wifi_internal_tx(uint32_t interface,const uint8_t *p,uint16_t n) {
 uint8_t copy[1536];int result=(int)wifi_packet_peer[0];unmasked();wifi_packet_peer[1]++;wifi_packet_peer[7]++;
 if(!p || n<14 || n>1536 || interface){wifi_packet_peer[2]|=2;wifi_packet_peer[7]--;return 999;}
 if(esp_wifi_tx_active<wifi_packet_peer[7])wifi_packet_peer[2]|=64;
 for(unsigned i=0;i<n;i++)copy[i]=p[i];
 if(wifi_packet_peer[12]){wifi_packet_peer[12]=0;phase(1,25);}
 for(unsigned i=0;i<n;i++)if(copy[i]!=p[i])wifi_packet_peer[2]|=8;
 wifi_packet_peer[7]--;return result;
}
void esp_wifi_internal_free_rx_buffer(void *p) {
 unmasked();wifi_packet_peer[3]++;wifi_packet_peer[8]++;
 if((uintptr_t)p!=0x1234 && (uintptr_t)p!=0x5678)wifi_packet_peer[2]|=2;
 if(esp_wifi_rx_callbacks<wifi_packet_peer[8])wifi_packet_peer[2]|=128;
 if(wifi_packet_peer[13]){wifi_packet_peer[13]=0;phase(2,wifi_packet_peer[15]?26:25);}
 wifi_packet_peer[8]--;
}
int esp_wifi_stop(void) {unmasked();wifi_packet_peer[4]++;if(wifi_packet_peer[7]||wifi_packet_peer[8])wifi_packet_peer[2]|=4;if(wifi_packet_peer[14]){wifi_packet_peer[14]=0;phase(3,25);}return (int)wifi_packet_peer[16];}
int esp_wifi_deinit_internal(void) {unmasked();wifi_packet_peer[17]++;if(wifi_packet_peer[7]||wifi_packet_peer[8])wifi_packet_peer[2]|=4;return (int)wifi_packet_peer[18];}
int esp_supplicant_deinit(void) {unmasked();return 0;}
int esp_wifi_start(void) {unmasked();return 0;}
int esp_wifi_set_ps(int n) {(void)n;unmasked();return 0;}
int esp_wifi_init_internal(void *p) {(void)p;unmasked();return 0;}
int esp_wifi_set_storage(int n) {(void)n;unmasked();return 0;}
int esp_wifi_set_mode(int n) {(void)n;unmasked();return 0;}
int esp_supplicant_init(void) {unmasked();return 0;}
int esp_wifi_internal_reg_rxcb(int n,void *p) {(void)n;(void)p;unmasked();return 0;}
void ets_delay_us(uint32_t n) {(void)n;}
void phy_init_param_set(int n) {(void)n;}
int register_chipv7_phy(void *a,void *b,int c) {(void)a;(void)b;(void)c;return 0;}
void phy_wakeup_init(void) {}
void phy_wifi_enable_set(int n) {(void)n;}
void phy_close_rf(void) {}
