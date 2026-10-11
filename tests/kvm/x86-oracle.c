// Differential oracle: real host x86 instructions produce results and flags.
#include <stdint.h>
#include <stdio.h>
#define EVAL(insn) __asm__ volatile("btq $0, %[carry]; " insn "; pushfq; popq %%rdx" : "+a"(result), "=d"(flags) : "c"(b), [carry]"r"((uint64_t)carry) : "cc")
#define WIDTH_CASE(index,suffix,src,dst) \
    case index: switch(op) { \
    case 0: EVAL("add" suffix " " src ", " dst); break; \
    case 1: EVAL("or" suffix " " src ", " dst); break; \
    case 2: EVAL("adc" suffix " " src ", " dst); break; \
    case 3: EVAL("sbb" suffix " " src ", " dst); break; \
    case 4: EVAL("and" suffix " " src ", " dst); break; \
    case 5: EVAL("sub" suffix " " src ", " dst); break; \
    case 6: EVAL("xor" suffix " " src ", " dst); break; \
    case 7: EVAL("cmp" suffix " " src ", " dst); break; } break
int main(int argc,char **argv) {
    if(argc!=2) return 1;
    FILE *out=fopen(argv[1],"wb");if(!out) return 2;
    const uint64_t values[]={0,1,15,16,127,128,255,256,32767,32768,65535,
        0x7fffffff,0x80000000,0xffffffff,0x7fffffffffffffff,0x8000000000000000,UINT64_MAX};
    const unsigned widths[]={1,2,4,8},ops[]={0,1,2,3,4,5,6,7};
    for(unsigned w=0;w<4;w++) for(unsigned o=0;o<8;o++) for(unsigned carry=0;carry<2;carry++)
    for(unsigned i=0;i<sizeof(values)/sizeof(values[0]);i++)
    for(unsigned j=0;j<sizeof(values)/sizeof(values[0]);j++) {
        uint64_t a=values[i],b=values[j],result=a,flags;unsigned op=ops[o];
        switch(widths[w]) {
            WIDTH_CASE(1,"b","%%cl","%%al");
            WIDTH_CASE(2,"w","%%cx","%%ax");
            WIDTH_CASE(4,"l","%%ecx","%%eax");
            WIDTH_CASE(8,"q","%%rcx","%%rax");
            default:return 3;
        }
        uint64_t record[]={widths[w],op|(carry<<8),a,b,result,flags};
        if(fwrite(record,sizeof(record),1,out)!=1) return 4;
    }
    return fclose(out)!=0;
}
