#include <stdint.h>
static __thread volatile uint64_t private_value=0x8877665544332211ULL;
static __thread volatile uint32_t private_id;
static __thread volatile uint32_t private_irqs;
static volatile uint32_t entered,completed,failed;
uint32_t preempt_tls_irq(void) {
    if (!private_id) return 0;
    if (private_id!=17 && private_id!=29 && private_id!=99) return 1;
    if (private_value!=(0x8877665544332211ULL^(uint64_t)private_id)) return 2;
    private_irqs++;
    return 0;
}
uint32_t preempt_tls_run(uint32_t id) {
    if (private_id || private_irqs || private_value!=0x8877665544332211ULL) {failed=1;return 1;}
    private_value=0x8877665544332211ULL^(uint64_t)id;
    private_id=id;
    uint32_t ps;
    __asm__ volatile("csrrc %0,mstatus,%1":"=r"(ps):"r"(8):"memory");
    entered|=id==17?1:id==29?2:4;
    __asm__ volatile("csrw mstatus,%0"::"r"(ps):"memory");
    volatile uint64_t words[16];
    for (uint32_t i=0;i<16;i++) words[i]=0x123456789abcdef0ULL+(uint64_t)(id*100+i);
    uint32_t timeout=0;
    while (private_irqs<5 || entered!=7) {
        for (uint32_t i=0;i<16;i++) if (words[i]!=0x123456789abcdef0ULL+(uint64_t)(id*100+i)) {failed=2;return 2;}
        if (private_value!=(0x8877665544332211ULL^(uint64_t)id)) {failed=3;return 3;}
        if (++timeout>1000000) {failed=4;return 4;}
    }
    __asm__ volatile("csrrc %0,mstatus,%1":"=r"(ps):"r"(8):"memory");
    completed|=id==17?1:id==29?2:4;
    __asm__ volatile("csrw mstatus,%0"::"r"(ps):"memory");
    return 0;
}
uint32_t preempt_tls_result(void) {return failed?100+failed:(completed==7?0:completed+1);}
