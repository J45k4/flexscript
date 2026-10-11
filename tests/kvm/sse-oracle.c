#include <stdint.h>
#include <stdio.h>

static void evaluate(unsigned op, const uint64_t a[2], const uint64_t b[2],
                     uint32_t mx, uint64_t out[2], uint32_t *status) {
    uint32_t csr;
#define OP(insn) __asm__ volatile("movdqu %2, %%xmm0; movdqu %3, %%xmm1; ldmxcsr %4; " insn "; movdqu %%xmm0, %0; stmxcsr %1" \
        : "=m"(*(uint64_t (*)[2])out), "=m"(csr) : "m"(*(const uint64_t (*)[2])a), "m"(*(const uint64_t (*)[2])b), "m"(mx) : "xmm0", "xmm1", "memory")
    switch (op) {
    case 0: OP("pxor %%xmm1, %%xmm0"); break;
    case 1: OP("paddq %%xmm1, %%xmm0"); break;
    case 2: OP("paddd %%xmm1, %%xmm0"); break;
    case 3: OP("psubb %%xmm1, %%xmm0"); break;
    case 4: OP("pmullw %%xmm1, %%xmm0"); break;
    case 5: OP("packsswb %%xmm1, %%xmm0"); break;
    case 6: OP("psrlw %%xmm1, %%xmm0"); break;
    case 7: OP("pshufd $0x1b, %%xmm1, %%xmm0"); break;
    case 8: OP("pslldq $3, %%xmm0"); break;
    case 9: OP("addps %%xmm1, %%xmm0"); break;
    case 10: OP("addpd %%xmm1, %%xmm0"); break;
    case 11: OP("addss %%xmm1, %%xmm0"); break;
    case 12: OP("addsd %%xmm1, %%xmm0"); break;
    case 13: OP("mulps %%xmm1, %%xmm0"); break;
    case 14: OP("divpd %%xmm1, %%xmm0"); break;
    default: OP("cmppd $3, %%xmm1, %%xmm0"); break;
    }
#undef OP
    *status=csr;
    uint32_t normal=0x1f80;
    __asm__ volatile("ldmxcsr %0" : : "m"(normal));
}
static void transfer(unsigned op, const uint64_t a[2], const uint64_t b[2],
                     uint64_t out[2], uint64_t *integer) {
    uint64_t value=a[0];
#define MOVE(insn) __asm__ volatile("movdqu %2, %%xmm0; movdqu %3, %%xmm1; " insn "; movdqu %%xmm0, %0" \
        : "=m"(*(uint64_t (*)[2])out), "+a"(value) : "m"(*(const uint64_t (*)[2])a), "m"(*(const uint64_t (*)[2])b) : "xmm0", "xmm1", "memory")
    switch (op) {
    case 0: MOVE("movd %%eax, %%xmm0"); break;
    case 1: MOVE("movq %%rax, %%xmm0"); break;
    case 2: MOVE("movd %%xmm1, %%eax"); break;
    case 3: MOVE("movq %%xmm1, %%rax"); break;
    case 4: MOVE("movq %%xmm1, %%xmm0"); break;
    case 5: MOVE("movq %%xmm1, %%xmm0"); break;
    case 6: MOVE("pmovmskb %%xmm1, %%eax"); break;
    case 7: MOVE("movmskps %%xmm1, %%eax"); break;
    case 8: MOVE("movmskpd %%xmm1, %%eax"); break;
    }
#undef MOVE
    *integer=value;
}
static void convert(unsigned op, uint64_t value, uint32_t mx, uint64_t out[2], uint32_t *status) {
    uint64_t initial[2]={0x1122334455667788ull,0x8877665544332211ull};
#define CONVERT(insn) __asm__ volatile("movdqu %2, %%xmm0; ldmxcsr %3; " insn "; movdqu %%xmm0, %0; stmxcsr %1" : "=m"(*(uint64_t (*)[2])out), "=m"(*status) : "m"(initial), "m"(mx), "a"(value) : "xmm0", "memory")
    switch(op) {
    case 0: CONVERT("cvtsi2ss %%eax, %%xmm0"); break;
    case 1: CONVERT("cvtsi2ss %%rax, %%xmm0"); break;
    case 2: CONVERT("cvtsi2sd %%eax, %%xmm0"); break;
    case 3: CONVERT("cvtsi2sd %%rax, %%xmm0"); break;
    }
#undef CONVERT
    uint32_t normal=0x1f80; __asm__ volatile("ldmxcsr %0"::"m"(normal));
}
static void compare_scalar(unsigned op,const uint64_t a[2],const uint64_t b[2],uint64_t *flags,uint32_t *status) {
    uint32_t mx=0x1f80;
#define COMPARE(insn) __asm__ volatile("movdqu %2, %%xmm0; movdqu %3, %%xmm1; ldmxcsr %4; " insn "; pushfq; popq %0; stmxcsr %1" : "=r"(*flags), "=m"(*status) : "m"(*(const uint64_t (*)[2])a), "m"(*(const uint64_t (*)[2])b), "m"(mx) : "xmm0", "xmm1", "cc", "memory")
    switch(op) {case 0: COMPARE("ucomiss %%xmm1, %%xmm0");break;case 1: COMPARE("ucomisd %%xmm1, %%xmm0");break;case 2: COMPARE("comiss %%xmm1, %%xmm0");break;case 3: COMPARE("comisd %%xmm1, %%xmm0");break;}
#undef COMPARE
}
static void convert_out(unsigned op,const uint64_t a[2],uint32_t mx,uint64_t *out,uint32_t *status) {
#define OUT(insn) __asm__ volatile("movdqu %2, %%xmm1; ldmxcsr %3; " insn "; stmxcsr %1" : "=a"(*out), "=m"(*status) : "m"(*(const uint64_t (*)[2])a), "m"(mx) : "xmm1", "memory")
    switch(op){case 0:OUT("cvttss2si %%xmm1, %%eax");break;case 1:OUT("cvttss2si %%xmm1, %%rax");break;case 2:OUT("cvttsd2si %%xmm1, %%eax");break;case 3:OUT("cvttsd2si %%xmm1, %%rax");break;case 4:OUT("cvtss2si %%xmm1, %%eax");break;case 5:OUT("cvtss2si %%xmm1, %%rax");break;case 6:OUT("cvtsd2si %%xmm1, %%eax");break;case 7:OUT("cvtsd2si %%xmm1, %%rax");break;}
#undef OUT
    uint32_t normal=0x1f80;__asm__ volatile("ldmxcsr %0"::"m"(normal));
}
static void convert_vector(unsigned op,const uint64_t a[2],const uint64_t b[2],uint32_t mx,uint64_t out[2],uint32_t *status) {
#define VECTOR(insn) __asm__ volatile("movdqu %2, %%xmm0; movdqu %3, %%xmm1; ldmxcsr %4; " insn "; movdqu %%xmm0, %0; stmxcsr %1" : "=m"(*(uint64_t (*)[2])out), "=m"(*status) : "m"(*(const uint64_t (*)[2])a), "m"(*(const uint64_t (*)[2])b), "m"(mx) : "xmm0", "xmm1", "memory")
    switch(op){case 0:VECTOR("cvtps2pd %%xmm1, %%xmm0");break;case 1:VECTOR("cvtpd2ps %%xmm1, %%xmm0");break;case 2:VECTOR("cvtss2sd %%xmm1, %%xmm0");break;case 3:VECTOR("cvtsd2ss %%xmm1, %%xmm0");break;case 4:VECTOR("cvtdq2ps %%xmm1, %%xmm0");break;case 5:VECTOR("cvtps2dq %%xmm1, %%xmm0");break;case 6:VECTOR("cvttps2dq %%xmm1, %%xmm0");break;case 7:VECTOR("cvtdq2pd %%xmm1, %%xmm0");break;case 8:VECTOR("cvtpd2dq %%xmm1, %%xmm0");break;case 9:VECTOR("cvttpd2dq %%xmm1, %%xmm0");break;}
#undef VECTOR
    uint32_t normal=0x1f80;__asm__ volatile("ldmxcsr %0"::"m"(normal));
}
int main(int argc, char **argv) {
    if (argc!=2) return 2;
    FILE *file=fopen(argv[1],"wb"); if (!file) return 2;
    const uint64_t values[]={0,~0ull,1,0x3f8000003f800000ull,0x3ff0000000000000ull,0x7ff0000000000000ull,0x7ff8000000000001ull,0x1234567887654321ull};
    for (unsigned r=0;r<4;++r) for (unsigned op=0;op<16;++op)
      for (unsigned a=0;a<8;++a) for (unsigned b=0;b<8;++b) {
        uint64_t row[10]={op,values[a],~values[a],values[b],~values[b],0x1f80|(r<<13),0,0,0,0};
        uint32_t status;
        evaluate(op,row+1,row+3,row[5],row+6,&status);row[8]=status;
        if (fwrite(row,sizeof(row),1,file)!=1) return 1;
      }
    for (unsigned op=0;op<9;++op) for (unsigned a=0;a<8;++a) {
        uint64_t row[10]={16+op,values[a],~values[a],values[(a+3)%8],~values[(a+3)%8],0,0,0,0,0};
        transfer(op,row+1,row+3,row+6,row+8);
        if (fwrite(row,sizeof(row),1,file)!=1) return 1;
    }
    const uint64_t integers[]={0,1,~0ull,0x80000000ull,0x7fffffffull,0x8000000000000000ull,0x7fffffffffffffffull,0x1234567887654321ull};
    for(unsigned r=0;r<4;++r) for(unsigned op=0;op<4;++op) for(unsigned i=0;i<8;++i) {
        uint64_t row[10]={32+op,integers[i],0,0,0,0x1f80|(r<<13),0,0,0,0};uint32_t status;
        convert(op,row[1],row[5],row+6,&status);row[8]=status;
        if(fwrite(row,sizeof(row),1,file)!=1)return 1;
    }
    const uint64_t floats[]={0,0x8000000080000000ull,0x3ff000003f800000ull,0xbff00000bf800000ull,0x7ff000007f800000ull,0x7ff800007fc00000ull,0x7ff000017f800001ull,0x0000000000000001ull};
    for(unsigned op=0;op<4;++op)for(unsigned a=0;a<8;++a)for(unsigned b=0;b<8;++b){
        uint64_t row[10]={40+op,floats[a],~floats[a],floats[b],~floats[b],0,0,0,0,0};uint32_t status;
        compare_scalar(op,row+1,row+3,row+6,&status);row[8]=status;
        if(fwrite(row,sizeof(row),1,file)!=1)return 1;
    }
    const uint64_t inputs[]={0,0x8000000080000000ull,0x3ff800003fc00000ull,0xbff80000bfc00000ull,0x7ff000007f800000ull,0x7ff800007fc00000ull,0x7ff000017f800001ull,0x0000000000000001ull,0x43e000005f000000ull,0xc3e00000df000000ull,0x41e000004f000000ull,0xc1e00000cf000000ull};
    for(unsigned r=0;r<4;++r)for(unsigned op=0;op<8;++op)for(unsigned i=0;i<12;++i){
        uint64_t row[10]={48+op,inputs[i],~inputs[i],0,0,0x1f80|(r<<13),0,0,0,0};uint32_t status;
        convert_out(op,row+1,row[5],row+6,&status);row[8]=status;
        if(fwrite(row,sizeof(row),1,file)!=1)return 1;
    }
    for(unsigned r=0;r<4;++r)for(unsigned op=0;op<10;++op)for(unsigned i=0;i<12;++i){
        uint64_t row[10]={56+op,0x1122334455667788ull,0x8877665544332211ull,inputs[i],inputs[(i+5)%12],0x1f80|(r<<13),0,0,0,0};uint32_t status;
        convert_vector(op,row+1,row+3,row[5],row+6,&status);row[8]=status;
        if(fwrite(row,sizeof(row),1,file)!=1)return 1;
    }
    return fclose(file)!=0;
}
