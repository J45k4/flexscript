/* Independent VHCI peer: unmasked calls, borrowed-buffer identity, busy C frames. */
#include <stdint.h>
typedef uint32_t (*callback_t)(uint32_t,uint32_t,uint32_t,uint32_t,uint32_t,uint32_t,uint32_t,uint32_t);
volatile uint32_t bt_concurrent[32];
static uint32_t invoke(uint32_t f,uint32_t a,uint32_t b) {return f?((callback_t)(uintptr_t)f)(a,b,0,0,0,0,0,0):0;}
static void ready(void) {invoke(bt_concurrent[4],0,0);}
uint32_t bt_concurrent_emit(uint32_t op,uint32_t status,uint32_t credits) {
    uint8_t reply[7]={4,14,4,(uint8_t)credits,(uint8_t)op,(uint8_t)(op>>8),(uint8_t)status};
    invoke(bt_concurrent[5],(uint32_t)(uintptr_t)reply,7);return 0;
}
static void phase(unsigned value) {
    uint32_t begin,now;bt_concurrent[24]=value;__asm__ volatile("rsr.ccount %0":"=a"(begin));
    do {if(bt_concurrent[25])return;__asm__ volatile("rsr.ccount %0":"=a"(now));}while((uint32_t)(now-begin)<8000000);
    bt_concurrent[2]|=16;
}
uint32_t API_vhci_host_check_send_available(void) {
    uint32_t ps;__asm__ volatile("rsr.ps %0":"=a"(ps));if(ps&15)bt_concurrent[2]|=1;bt_concurrent[10]++;
    if(bt_concurrent[8]) {uint32_t status=bt_concurrent[8];bt_concurrent[8]=0;bt_concurrent_emit(bt_concurrent[9],status,bt_concurrent[23]);if(!bt_concurrent[23])bt_concurrent[24]=3;}
    if(bt_concurrent[12]){bt_concurrent[12]=0;phase(1);}return bt_concurrent[0];
}
void API_vhci_host_send_packet(uint8_t *p,uint32_t n) {
    uint32_t ps;uint8_t copy[1032];__asm__ volatile("rsr.ps %0":"=a"(ps));if(ps&15)bt_concurrent[2]|=1;
    if(!p || n>1032){bt_concurrent[2]|=2;return;}if(bt_concurrent[15])bt_concurrent[2]|=8;
    bt_concurrent[15]++;bt_concurrent[1]++;bt_concurrent[19]=(uint32_t)(uintptr_t)p;
    for(uint32_t i=0;i<n;i++)copy[i]=p[i];
    if(bt_concurrent[11])ready();
    if(bt_concurrent[13]){bt_concurrent[13]=0;phase(2);}
    for(uint32_t i=0;i<n;i++)if(copy[i]!=p[i])bt_concurrent[2]|=4;
    if(p[0]==1 && n>=4){uint32_t op=p[1]|((uint32_t)p[2]<<8);bt_concurrent[9]=op;if(op!=0x0c35 && !bt_concurrent[6])bt_concurrent_emit(op,bt_concurrent[7],1);}
    if(!bt_concurrent[11])ready();bt_concurrent[15]--;
}
void btdm_controller_deinit(void) {bt_concurrent[16]++;}
void phy_close_rf(void) {bt_concurrent[17]++;}
