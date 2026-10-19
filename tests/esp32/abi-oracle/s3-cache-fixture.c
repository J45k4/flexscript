#include <stdint.h>
extern const uint8_t s3_cache_bytes[];
__attribute__((noinline,aligned(65536)))
uint32_t s3_cache_sum(uint32_t begin,uint32_t size) {
    const volatile uint8_t *p=s3_cache_bytes+begin;uint32_t result=0;
    for (uint32_t i=0;i<size;i++) result+=(uint32_t)p[i]*(i+1);
    return result;
}
__attribute__((section(".dram1.s3_fixture"),used))
const uint32_t s3_cache_dram[2]={0xcafebabe,0x12345678};
__attribute__((section(".phyiram.s3_fixture"),noinline))
uint32_t s3_cache_iram(uint32_t n) {return n ^ UINT32_C(0xabc12345);}
