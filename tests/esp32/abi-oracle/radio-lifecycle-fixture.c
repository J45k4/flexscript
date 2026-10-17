// Independent C peer exercises the real native OSI ABI and lifecycle facade.
#include <stdint.h>
typedef uint32_t (*callback_t)(uint32_t,uint32_t,uint32_t,uint32_t,uint32_t,uint32_t,uint32_t,uint32_t);
uint32_t g_wifi_osi_funcs[121],g_wifi_default_wpa_crypto_funcs[13];
const char *WIFI_EVENT;
uint32_t s_wifi_api_lock,g_wifi_global_lock,eloop_data_lock;
volatile uint32_t wifi_lifecycle_oracle[32];
static uint32_t osi(unsigned offset,uint32_t a,uint32_t b,uint32_t c,uint32_t d,uint32_t e,uint32_t f,uint32_t g) {return ((callback_t)(uintptr_t)g_wifi_osi_funcs[offset/4])(a,b,c,d,e,f,g,0);}
static int step(unsigned n) {uint32_t ps;__asm__ volatile("rsr.ps %0":"=a"(ps));if(ps&15)return 995;wifi_lifecycle_oracle[n+8]++;return (wifi_lifecycle_oracle[0]==n||wifi_lifecycle_oracle[1]==n)?(int)(700+n):0;}
static void irq(void *p) {(void)p;}
static void worker(void *p) {(void)p;}
static uint32_t task;
void ets_delay_us(uint32_t n) {(void)n;}
void phy_init_param_set(int n) {(void)n;}
int register_chipv7_phy(void *a,void *b,int c) {(void)a;(void)b;(void)c;return 0;}
void phy_wakeup_init(void) {}
void phy_wifi_enable_set(int n) {(void)n;}
void phy_close_rf(void) {}
int esp_wifi_init_internal(const void *cfg) {
 (void)cfg;int r=step(1);if(r)return r;
 if(!s_wifi_api_lock)s_wifi_api_lock=osi(76,0,0,0,0,0,0,0);
 if(!g_wifi_global_lock)g_wifi_global_lock=osi(72,0,0,0,0,0,0,0);
 if(!eloop_data_lock)eloop_data_lock=osi(72,0,0,0,0,0,0,0);
 uint32_t *locks[3]={(uint32_t *)(uintptr_t)s_wifi_api_lock,(uint32_t *)(uintptr_t)g_wifi_global_lock,(uint32_t *)(uintptr_t)eloop_data_lock};
 for(unsigned i=0;i<3;i++)if(!locks[i] || locks[i][-1]!=0x48454150 || (locks[i][-4]&15)!=3)return 996;
 if(!osi(52,1,0,0,0,0,0,0)||!osi(68,0,0,0,0,0,0,0))return 999;
 if(osi(16,0,(uint32_t)(uintptr_t)irq,0,0,0,0,0))return 998;
 if(!osi(144,(uint32_t)(uintptr_t)worker,0,4096,0,3,(uint32_t)(uintptr_t)&task,0))return 997;
 return 0;
}
int esp_wifi_set_storage(int n) {(void)n;return step(2);}
int esp_wifi_set_mode(int n) {(void)n;return step(3);}
int esp_supplicant_init(void) {return step(4);}
int esp_wifi_internal_reg_rxcb(int n,void *p) {(void)n;(void)p;return step(5);}
int esp_wifi_start(void) {return step(6);}
int esp_wifi_set_ps(int n) {(void)n;return step(7);}
int esp_wifi_stop(void) {return step(8);}
int esp_wifi_deinit_internal(void) {int r=step(9);if(!r && task){osi(152,task,0,0,0,0,0,0);task=0;}return r;}
int esp_supplicant_deinit(void) {return step(10);}
void esp_wifi_internal_free_rx_buffer(void *p) {(void)p;}

void btdm_controller_deinit(void) {wifi_lifecycle_oracle[31]++;}
