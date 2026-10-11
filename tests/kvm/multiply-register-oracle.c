#include <stdint.h>
#include <stdio.h>

int main(int argc, char **argv) {
    if (argc != 2) return 1;
    FILE *out = fopen(argv[1], "wb");
    if (!out) return 1;
    const uint64_t values[] = {0,1,2,3,7,255,256,0x7fffffff,0x80000000,
        0xffffffff,0x100000000,0x7fffffffffffffff,0x8000000000000000,
        0x8000000000000001,0xfffffffffffffffe,UINT64_MAX,0x123456789abcdef0};
    for (unsigned width = 4; width <= 8; width *= 2) {
        for (unsigned sign = 0; sign < 2; sign++) {
            for (unsigned i = 0; i < sizeof(values)/sizeof(*values); i++) {
                for (unsigned j = 0; j < sizeof(values)/sizeof(*values); j++) {
                    uint64_t a=values[i], b=values[j], lo=a, hi=0, flags;
                    if (width == 8) {
                        if (sign) __asm__ volatile("imulq %3; pushfq; popq %2" : "+a"(lo), "=d"(hi), "=r"(flags) : "r"(b) : "cc");
                        else __asm__ volatile("mulq %3; pushfq; popq %2" : "+a"(lo), "=d"(hi), "=r"(flags) : "r"(b) : "cc");
                    } else {
                        uint32_t l=(uint32_t)a, h;
                        if (sign) __asm__ volatile("imull %3; pushfq; popq %2" : "+a"(l), "=d"(h), "=r"(flags) : "r"((uint32_t)b) : "cc");
                        else __asm__ volatile("mull %3; pushfq; popq %2" : "+a"(l), "=d"(h), "=r"(flags) : "r"((uint32_t)b) : "cc");
                        lo=l; hi=h;
                    }
                    uint64_t row[8]={width,sign,a,b,lo,hi,flags,0};
                    if (fwrite(row,sizeof(row),1,out)!=1) return 1;
                }
            }
        }
    }
    return fclose(out)!=0;
}
