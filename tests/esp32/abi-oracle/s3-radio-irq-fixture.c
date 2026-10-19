#include <stdint.h>
#define __ASSEMBLER__ 1
#include "soc/interrupts.h"
#include "soc/interrupt_core0_reg.h"
volatile uint32_t c_s3_irq_counts[4];
static uint32_t check(uint32_t pointer,uint32_t tag,unsigned slot) {
    volatile const uint32_t *p=(volatile const uint32_t *)(uintptr_t)pointer;
    uint32_t ps;__asm__ volatile("rsr.ps %0":"=a"(ps));
    c_s3_irq_counts[slot]++;
    if(!p || p[0]!=tag || p[1]!=0x13572468 || p[2]!=0x24681357 || !(ps&15))c_s3_irq_counts[2]++;
    return 0;
}
uint32_t c_s3_irq_old(uint32_t p) {return check(p,0x4f4c4421,0);}
uint32_t c_s3_irq_new(uint32_t p) {return check(p,0x4e455721,1);}
uint32_t c_s3_irq_contract(unsigned i) {
    static const uint32_t values[]={ETS_WIFI_MAC_INTR_SOURCE,ETS_WIFI_PWR_INTR_SOURCE,
        INTERRUPT_CORE0_MAC_INTR_MAP_REG,INTERRUPT_CORE0_PWR_INTR_MAP_REG,
        INTERRUPT_CORE0_INTR_STATUS_0_REG};
    return i<5?values[i]:0xffffffff;
}
