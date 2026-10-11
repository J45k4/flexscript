#include <stdint.h>
#include <stdio.h>

static void evaluate(unsigned op, uint64_t a, uint64_t b, uint64_t row[8]) {
    unsigned char host[512] __attribute__((aligned(16)));
    unsigned char guest[512] __attribute__((aligned(16)));
    uint64_t result;
#define MMX(insn) __asm__ volatile("fxsave64 %1; fninit; movq %3, %%mm3; movq %4, %%mm5; " insn "; movq %%mm3, %0; fxsave64 %2; emms; fxrstor64 %1" \
    : "=m"(result), "=m"(host), "=m"(guest) : "m"(a), "m"(b) : "mm3", "mm5", "memory")
    switch (op) {
    case 0: MMX("pxor %%mm5, %%mm3"); break;
    case 1: MMX("paddb %%mm5, %%mm3"); break;
    case 2: MMX("paddsw %%mm5, %%mm3"); break;
    case 3: MMX("psubusw %%mm5, %%mm3"); break;
    case 4: MMX("pmullw %%mm5, %%mm3"); break;
    case 5: MMX("pmulhw %%mm5, %%mm3"); break;
    case 6: MMX("pmaddwd %%mm5, %%mm3"); break;
    case 7: MMX("packsswb %%mm5, %%mm3"); break;
    case 8: MMX("punpckhbw %%mm5, %%mm3"); break;
    case 9: MMX("pcmpeqd %%mm5, %%mm3"); break;
    case 10: MMX("pcmpgtw %%mm5, %%mm3"); break;
    case 11: MMX("psrlw %%mm5, %%mm3"); break;
    case 12: MMX("psraw $7, %%mm3"); break;
    case 13: MMX("psllq $63, %%mm3"); break;
    case 14: MMX("pandn %%mm5, %%mm3"); break;
    case 15: MMX("paddq %%mm5, %%mm3"); break;
    }
#undef MMX
    row[0]=op; row[1]=a; row[2]=b; row[3]=result;
    row[4]=guest[0]|((unsigned)guest[1]<<8);
    row[5]=guest[2]|((unsigned)guest[3]<<8);
    row[6]=guest[4]; row[7]=guest[32+3*16+8]|((unsigned)guest[32+3*16+9]<<8);
}
int main(int argc, char **argv) {
    if (argc!=2) return 2;
    FILE *file=fopen(argv[1],"wb"); if (!file) return 2;
    const uint64_t values[]={0,~0ull,1,7,63,0x80007fff00ff8000ull,0x7fffffff80000000ull,0x1234567887654321ull};
    for (unsigned op=0;op<16;++op) for (unsigned a=0;a<8;++a) for (unsigned b=0;b<8;++b) {
        uint64_t row[8]; evaluate(op,values[a],values[b],row);
        if (fwrite(row,sizeof(row),1,file)!=1) return 1;
    }
    for (unsigned match=0;match<2;++match) for (unsigned a=0;a<8;++a) for (unsigned b=0;b<8;++b) {
        uint64_t memory=values[a], input=values[a]^(!match);
        uint32_t low=input, high=input>>32;unsigned char equal;
        __asm__ volatile("lock cmpxchg8b %0; setz %3"
            : "+m"(memory), "+a"(low), "+d"(high), "=qm"(equal)
            : "b"((uint32_t)values[b]), "c"((uint32_t)(values[b]>>32)) : "cc", "memory");
        uint64_t row[8]={100,values[a],values[b],input,memory,low|((uint64_t)high<<32),equal,0};
        if (fwrite(row,sizeof(row),1,file)!=1) return 1;
    }
    return fclose(file)!=0;
}
