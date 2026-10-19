/* Independent C peer validates callback/argument identity during real IRQs. */
#include <stdint.h>
volatile uint32_t c_irq_publication[4];
static uint32_t check(uint32_t pointer,uint32_t tag,unsigned slot) {
    volatile const uint32_t *p=(volatile const uint32_t *)(uintptr_t)pointer;
    c_irq_publication[slot]++;
    if(!p || p[0]!=tag || p[1]!=0x13572468 || p[2]!=0x24681357)c_irq_publication[2]++;
    return 0;
}
uint32_t c_irq_old(uint32_t pointer) {return check(pointer,0x4f4c4421,0);}
uint32_t c_irq_new(uint32_t pointer) {return check(pointer,0x4e455721,1);}
