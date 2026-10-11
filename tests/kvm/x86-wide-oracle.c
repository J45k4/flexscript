#include <stdint.h>
#include <stdio.h>

int main(int argc, char **argv) {
    if (argc != 2) return 1;
    FILE *out = fopen(argv[1], "wb");
    if (!out) return 1;
    const uint64_t values[] = {0,1,2,3,7,255,256,0x7fffffff,0x80000000,
        0xffffffff,0x100000000,0x7fffffffffffffff,0x8000000000000000,
        0x8000000000000001,0xfffffffffffffffe,UINT64_MAX,0x123456789abcdef0};
    for (unsigned group = 4; group <= 7; group++) {
        for (unsigned i = 0; i < sizeof(values)/sizeof(*values); i++) {
            for (unsigned j = 0; j < sizeof(values)/sizeof(*values); j++) {
                uint64_t a=values[i], b=values[j], hi=0, lo=a, flags=0;
                if (group >= 6 && !b) continue;
                if (group == 6) hi=a%b;
                if (group == 7) {
                    if (a==0x8000000000000000 && b==UINT64_MAX) continue;
                    hi=(int64_t)a < 0 ? UINT64_MAX : 0;
                }
                uint64_t record[8]={group,8,a,hi,b,0,0,0};
                switch (group) {
                case 4: __asm__ volatile("mulq %3; pushfq; popq %2" : "+a"(lo), "+d"(hi), "=r"(flags) : "r"(b) : "cc"); break;
                case 5: __asm__ volatile("imulq %3; pushfq; popq %2" : "+a"(lo), "+d"(hi), "=r"(flags) : "r"(b) : "cc"); break;
                case 6: __asm__ volatile("divq %2" : "+a"(lo), "+d"(hi) : "r"(b) : "cc"); break;
                case 7: __asm__ volatile("idivq %2" : "+a"(lo), "+d"(hi) : "r"(b) : "cc"); break;
                }
                record[5]=lo;record[6]=hi;record[7]=flags;
                if (fwrite(record,sizeof(record),1,out)!=1) return 1;
            }
        }
    }
    return fclose(out)!=0;
}
