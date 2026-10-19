#include <stdint.h>
const unsigned char xip_constants[143373] = {[0]=17,[65535]=29,[65536]=43,[131071]=61,[143372]=89};
extern void Cache_Disable_ICache(void);
extern void Cache_Enable_ICache(unsigned);
extern unsigned xip_irq_seen;
typedef unsigned (*callback_t)(unsigned,unsigned,unsigned,unsigned,unsigned,unsigned,unsigned,unsigned);
unsigned xip_constant(unsigned index){return ((volatile const unsigned char*)xip_constants)[index];}
unsigned xip_constant_address(void){return (unsigned)(uintptr_t)xip_constants;}
__attribute__((noinline)) unsigned xip_long_code(unsigned value){
 __asm__ volatile(".rept 40000\n.4byte 0x00000013\n.endr");return value+29;
}
__attribute__((noinline,section(".iram1"))) unsigned xip_cache_off(callback_t fn,unsigned irq){
 unsigned ps;__asm__ volatile("csrr %0,mstatus":"=r"(ps));
 Cache_Disable_ICache();
 unsigned result=fn(7,11,13,17,19,23,29,31);
 if(irq){
#ifdef C6
  *(volatile unsigned*)0x600c5090=1;
#else
  *(volatile unsigned*)0x600c0028=1;
#endif
  __asm__ volatile("fence iorw,iorw":::"memory");
  for(unsigned i=0;i<1000000 && !*(volatile unsigned*)&xip_irq_seen;i++)__asm__ volatile("nop");
  if(!xip_irq_seen)result=0xbad;
 }
 __asm__ volatile("csrci mstatus,8":::"memory");
 Cache_Enable_ICache(0);__asm__ volatile("fence.i":::"memory");
 __asm__ volatile("csrw mstatus,%0"::"r"(ps):"memory");
 return result;
}
