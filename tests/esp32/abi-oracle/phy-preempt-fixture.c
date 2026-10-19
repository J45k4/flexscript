/* Independent GNU C PHY peer; no scheduler or production reference logic. */
#include <stdint.h>
volatile uint32_t phy_peer[16];
volatile uint32_t phy_clock_register;
extern volatile uint64_t esp_radio_phy_clock_refs;
static const uint8_t expected[128]={
 [0]=3,[1]=3,[2]=5,[3]=9,[4]=6,[5]=5,[6]=3,[7]=6,[8]=5,[9]=4,[10]=6,[11]=4,[12]=5,
 [17]=5,[18]=9,[19]=6,[20]=5,[21]=3,[22]=6,[23]=5,[32]=252,[33]=252,[34]=254,
 [35]=240,[36]=240,[37]=240,[38]=224,[39]=224,[40]=224,[41]=24,[42]=24,[43]=24,
 [44]=80,[45]=72,[46]=66,[47]=60,[48]=56,[49]=52,[51]=1,[52]=1,[53]=2,[54]=2,[55]=3,[56]=4,[57]=5};
static int allocated(uint32_t p) {return p && !(p&15) && ((volatile uint32_t *)(uintptr_t)p)[-1]==0x48454150 && (((volatile uint32_t *)(uintptr_t)p)[-4]&1);}
static void probe(void) {
 uint32_t ps,begin,now;phy_peer[7]++;
 __asm__ volatile("rsr.ps %0":"=a"(ps));if(!(ps&15))phy_peer[0]|=1;
 if(!esp_radio_phy_clock_refs)phy_peer[0]|=2;
 if(phy_peer[14] && ((*(volatile uint32_t *)(uintptr_t)phy_peer[14]&0x3c9)!=0x3c9))phy_peer[0]|=2;
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
