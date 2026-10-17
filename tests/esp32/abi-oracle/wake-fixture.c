/* Independent pinned radio bool-pointer ABI peer; no production C runtime. */
#include <stdint.h>
_Static_assert(sizeof(_Bool)==1,"pinned radio wake flag is one byte");
typedef uint32_t (*callback_t)(uint32_t,uint32_t,uint32_t,uint32_t,uint32_t,uint32_t,uint32_t,uint32_t);
uint32_t c_wake_calls;
uint32_t c_wake_invoke(uint32_t address,uint32_t object,uint32_t item,uint32_t sem_shape,uint32_t flags,uint32_t expected_result,uint32_t expected_flag,uint32_t chain) {
    volatile uint8_t guard[12];for(unsigned i=0;i<12;i++)guard[i]=0xa0+i;
    unsigned at=(flags&512)?3:4;guard[at]=flags&1;
    /* Test both aligned and unaligned bool pointers with surrounding byte guards. */
    uint32_t flag=(flags&256)?0:(uint32_t)(uintptr_t)&guard[at];
    callback_t callback=(callback_t)(uintptr_t)address;
    uint32_t before,after;__asm__ volatile("rsr.ps %0":"=a"(before));
    uint32_t result=callback(object,sem_shape?flag:item,sem_shape?0:flag,0,0,0,0,0);c_wake_calls++;
    if(result!=expected_result)return 1;
    if(chain && callback(0,sem_shape?flag:item,sem_shape?0:flag,0,0,0,0,0)!=0)return 4;
    __asm__ volatile("rsr.ps %0":"=a"(after));
    if((before&15)!=(after&15))return 3;
    if(guard[at]!=expected_flag)return 2;
    for(unsigned i=0;i<12;i++)if(i!=at && guard[i]!=0xa0+i)return 10+i;
    return 0;
}
