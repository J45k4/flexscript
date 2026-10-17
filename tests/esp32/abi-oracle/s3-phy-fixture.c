/* Independent GNU C PHY peer; no scheduler or production reference logic. */
#include <stdint.h>
volatile uint32_t phy_peer[16];
volatile uint32_t phy_clock_register;
extern volatile uint64_t esp_radio_phy_clock_refs;
static const uint8_t expected[128]={0,0,80,80,80,76,76,72,76,72,72,68,74,70,70,66,0,0,0,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,116,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0};
static int allocated(uint32_t p) {return p && !(p&15) && ((volatile uint32_t *)(uintptr_t)p)[-1]==0x48454150 && (((volatile uint32_t *)(uintptr_t)p)[-4]&1);}
static void probe(void) {
 uint32_t ps,begin,now;phy_peer[7]++;
 __asm__ volatile("rsr.ps %0":"=a"(ps));if(!(ps&15))phy_peer[0]|=1;
 if(!esp_radio_phy_clock_refs)phy_peer[0]|=2;
 if(phy_peer[14] && ((*(volatile uint32_t *)(uintptr_t)phy_peer[14]&0x78078f)!=0x78078f))phy_peer[0]|=2;
 __asm__ volatile("wsr.intset %0\nrsync"::"a"(128):"memory");
 __asm__ volatile("rsr.ccount %0":"=a"(begin));do{__asm__ volatile("rsr.ccount %0":"=a"(now));}while((uint32_t)(now-begin)<20000);
 phy_peer[7]--;
}
static void buffers(int calibrated) {
 uint8_t *cal=(uint8_t *)(uintptr_t)phy_peer[9],*data=(uint8_t *)(uintptr_t)phy_peer[10];
 if(!allocated(phy_peer[9]) || !allocated(phy_peer[10])){phy_peer[0]|=8;return;}
 for(unsigned i=0;i<128;i++)if(data[i]!=expected[i])phy_peer[0]|=8;
 for(unsigned i=0;i<1904;i++)if(cal[i]!=(calibrated?(uint8_t)(i*13+7):0))phy_peer[0]|=8;
}
void phy_init_param_set(int n) {probe();phy_peer[12]++;if(n!=1)phy_peer[0]|=4;}
int register_chipv7_phy(void *data,void *cal,int mode) {
 probe();phy_peer[1]++;if(mode!=2 || phy_peer[5])phy_peer[0]|=16;
 phy_peer[9]=(uint32_t)(uintptr_t)cal;phy_peer[10]=(uint32_t)(uintptr_t)data;buffers(0);
 if(allocated(phy_peer[9]))for(unsigned i=0;i<1904;i++)((uint8_t *)cal)[i]=(uint8_t)(i*13+7);
 phy_peer[5]=1;return (int)phy_peer[13];
}
void phy_wakeup_init(void) {probe();phy_peer[2]++;if(phy_peer[5])phy_peer[0]|=16;buffers(1);phy_peer[5]=1;}
void phy_close_rf(void) {probe();phy_peer[3]++;if(!phy_peer[5])phy_peer[0]|=16;buffers(1);phy_peer[5]=0;}
void phy_wifi_enable_set(int on) {probe();phy_peer[4]++;if(on && !phy_peer[5])phy_peer[0]|=16;phy_peer[6]=on!=0;}
uint32_t phy_peer_validate(uint32_t active) {if(phy_peer[5]!=(active!=0))phy_peer[0]|=16;if(active)buffers(1);return phy_peer[0];}

volatile uint32_t s3_phy_extra[8];
void phy_bbpll_en_usb(_Bool enabled) {probe();s3_phy_extra[0]++;if(!enabled)phy_peer[0]|=64;}
uint8_t phy_dig_reg_backup(_Bool backup,uint32_t *p) {
 probe();buffers(1);if(!allocated((uint32_t)(uintptr_t)p) || p[-2]<84 || !phy_peer[5]){phy_peer[0]|=128;return 1;}
 if(backup) {s3_phy_extra[1]++;for(unsigned i=0;i<21;i++)p[i]=0x12340000+i*0x12345;}
 else {s3_phy_extra[2]++;for(unsigned i=0;i<21;i++)if(p[i]!=0x12340000+i*0x12345)phy_peer[0]|=128;}
 return 0;
}
void phy_xpd_tsens(void) {probe();s3_phy_extra[3]++;if(phy_peer[5])phy_peer[0]|=256;}
