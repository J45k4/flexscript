#include <stdint.h>
#include <stdio.h>

static void shift(unsigned width, unsigned right, unsigned immediate,
                  uint64_t a, uint64_t b, unsigned count,
                  uint64_t *result, uint64_t *flags) {
    uint64_t f;
#define SHIFT(insn) __asm__ volatile("pushq $0xad7; popfq; " insn "; pushfq; popq %1" \
    : "+a"(a), "=r"(f) : "d"(b), "c"((uint64_t)count) : "cc")
    if (immediate) {
        if (width == 2) { if (right) SHIFT("shrdw $1, %%dx, %%ax"); else SHIFT("shldw $1, %%dx, %%ax"); }
        else if (width == 4) { if (right) SHIFT("shrdl $1, %%edx, %%eax"); else SHIFT("shldl $1, %%edx, %%eax"); }
        else { if (right) SHIFT("shrdq $1, %%rdx, %%rax"); else SHIFT("shldq $1, %%rdx, %%rax"); }
    } else {
        if (width == 2) { if (right) SHIFT("shrdw %%cl, %%dx, %%ax"); else SHIFT("shldw %%cl, %%dx, %%ax"); }
        else if (width == 4) { if (right) SHIFT("shrdl %%cl, %%edx, %%eax"); else SHIFT("shldl %%cl, %%edx, %%eax"); }
        else { if (right) SHIFT("shrdq %%cl, %%rdx, %%rax"); else SHIFT("shldq %%cl, %%rdx, %%rax"); }
    }
#undef SHIFT
    *result = a; *flags = f;
}
int main(int argc, char **argv) {
    if (argc != 2) return 2;
    FILE *file = fopen(argv[1], "wb"); if (!file) return 2;
    const uint64_t values[] = {0, 1, ~0ull, 0x8000000000000000ull, 0x1234567887654321ull, 0xaaaaaaaa55555555ull};
    const unsigned widths[] = {2,4,8};
    const unsigned counts[] = {0,1,2,15,16,31,32,63,64,65,255};
    for (unsigned w=0; w<3; ++w) for (unsigned right=0; right<2; ++right)
      for (unsigned a=0; a<6; ++a) for (unsigned b=0; b<6; ++b)
        for (unsigned c=0; c<12; ++c) {
            unsigned immediate=c==11, count=immediate?1:counts[c];
            unsigned effective=count & (widths[w]==8?63:31);
            if (effective>widths[w]*8) continue;
            uint64_t row[8]={widths[w],right|(immediate<<8),values[a],values[b],count,0,0,0};
            shift(row[0],right,immediate,row[2],row[3],count,&row[5],&row[6]);
            if (fwrite(row,sizeof(row),1,file)!=1) return 1;
        }
    return fclose(file)!=0;
}
