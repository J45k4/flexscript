/* Independent windowed ABI peer: control frames, inline events and credentials. */
#include <stdint.h>
typedef uint32_t (*callback_t)(uint32_t,uint32_t,uint32_t,uint32_t,uint32_t,uint32_t,uint32_t,uint32_t);
volatile uint32_t wifi_control_peer[32];
uint32_t g_wifi_osi_funcs[121],g_wifi_default_wpa_crypto_funcs[13];
const char *WIFI_EVENT;
uint32_t s_wifi_api_lock,g_wifi_global_lock,eloop_data_lock;
extern volatile uint64_t esp_wifi_control_active;
static void enter(void) {
 uint32_t ps;__asm__ volatile("rsr.ps %0":"=a"(ps));if(ps&15)wifi_control_peer[2]|=1;
 if(!esp_wifi_control_active)wifi_control_peer[2]|=2;if(wifi_control_peer[7]++)wifi_control_peer[2]|=4;
}
static void phase(unsigned value) {
 uint32_t begin,now;wifi_control_peer[24]=value;
 /* Publish the C-frame rendezvous through the real software interrupt. */
 __asm__ volatile("wsr.intset %0\nrsync"::"a"(128):"memory");
 __asm__ volatile("rsr.ccount %0":"=a"(begin));
 do{if(wifi_control_peer[25])return;__asm__ volatile("rsr.ccount %0":"=a"(now));}while((uint32_t)(now-begin)<8000000);
 wifi_control_peer[2]|=8;
}
uint32_t wifi_control_emit(uint32_t id) {
 volatile uint8_t data[40];for(unsigned i=0;i<40;i++)data[i]=0;data[33]=0xa1;data[38]=0xb2;data[39]=id==4?6:201;
 callback_t cb=(callback_t)(uintptr_t)wifi_control_peer[4];if(cb)cb(0,id,(uint32_t)(uintptr_t)data,40,0,0,0,0);return 0;
}
static void event(unsigned index) {unsigned id=wifi_control_peer[index];wifi_control_peer[index]=0;if(id)wifi_control_emit(id);}
int esp_wifi_set_config(uint32_t iface,const uint8_t *p) {
 enter();wifi_control_peer[1]++;wifi_control_peer[19]=(uint32_t)(uintptr_t)p;
 if(iface || !p || p[0]!='t' || p[32]!='t' || p[96]!=1 || p[116]!=157 || p[120]!=3 || p[128]!=1 || p[136]!=3)wifi_control_peer[2]|=16;
 uint8_t copy[184];for(unsigned i=0;i<184;i++)copy[i]=p[i];
 if(wifi_control_peer[12]){wifi_control_peer[12]=0;phase(1);}
 for(unsigned i=0;i<184;i++)if(copy[i]!=p[i])wifi_control_peer[2]|=32;
 event(15);wifi_control_peer[7]--;return (int)wifi_control_peer[0];
}
int esp_wifi_connect_internal(void) {enter();wifi_control_peer[3]++;if(wifi_control_peer[13]){wifi_control_peer[13]=0;phase(2);}event(16);wifi_control_peer[7]--;return (int)wifi_control_peer[8];}
int esp_wifi_disconnect_internal(void) {enter();wifi_control_peer[5]++;if(wifi_control_peer[20]){uint32_t start,now;__asm__ volatile("rsr.ccount %0":"=a"(start));do{__asm__ volatile("rsr.ccount %0":"=a"(now));}while((uint32_t)(now-start)<4000000);}if(wifi_control_peer[14]){wifi_control_peer[14]=0;phase(3);}event(17);if(wifi_control_peer[21]){uint32_t start,now;__asm__ volatile("rsr.ccount %0":"=a"(start));do{__asm__ volatile("rsr.ccount %0":"=a"(now));}while((uint32_t)(now-start)<4000000);}wifi_control_peer[7]--;return (int)wifi_control_peer[9];}
static int lifecycle(unsigned index) {uint32_t ps;__asm__ volatile("rsr.ps %0":"=a"(ps));if(ps&15)wifi_control_peer[2]|=1;if(wifi_control_peer[7])wifi_control_peer[2]|=64;wifi_control_peer[index]++;return 0;}
int esp_wifi_stop(void) {return lifecycle(10);}
int esp_wifi_deinit_internal(void) {return lifecycle(11);}
int esp_supplicant_deinit(void) {return 0;}
int esp_wifi_start(void) {return lifecycle(18);}
int esp_wifi_set_ps(int n) {(void)n;return 0;}
void esp_wifi_internal_free_rx_buffer(void *p) {(void)p;}
void phy_close_rf(void) {}
