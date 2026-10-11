#define _GNU_SOURCE
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
static void emit(uint8_t *p, size_t *n, uint64_t v, unsigned bytes) {
    for (unsigned i=0;i<bytes;i++) p[(*n)++]=(uint8_t)(v>>(i*8));
}
// Emit only fixed TEST/SETcc templates into a W^X page. No guest code or guest
// address executes here. TEST's undefined AF is excluded from native results;
// the software CPU separately checks its deterministic cleared-AF contract.
int main(int argc,char **argv) {
    if(argc!=2) return 2;
    FILE *out=fopen(argv[1],"wb"); if(!out) return 1;
    uint8_t *p=mmap(NULL,4096,PROT_READ|PROT_WRITE,MAP_PRIVATE|MAP_ANONYMOUS,-1,0);
    if(p==MAP_FAILED) return 1;
    uint64_t (*native)(uint64_t,uint64_t); memcpy(&native,&p,sizeof(native));
    const uint64_t values[]={0,1,0x80,0xff,0x8000,0xffff,0x80000000,0xffffffff,
        0x100000000,0x8000000000000000,0xffffffff00000000,UINT64_MAX,0x0123456789abcdef,0xfedcba9876543210};
    const uint32_t immediates[]={0,1,0xffffff9f,0x80000000,0xffffffff};
    for(unsigned width=1;width<=8;width*=2) for(unsigned form=0;form<2;form++)
    for(unsigned k=0;k<5;k++) {
        size_t n=0; emit(p,&n,0xf88948,3); emit(p,&n,0x9d56,2); // mov rdi,rax; push rsi; popfq
        if(width==2) emit(p,&n,0x66,1);
        if(width==8) emit(p,&n,0x48,1);
        emit(p,&n,form?(width==1?0xf6:0xf7):(width==1?0xa8:0xa9),1);
        if(form) emit(p,&n,0xc0,1);
        emit(p,&n,immediates[k],width==8?4:width); emit(p,&n,0xc3fc589c,4); // capture flags, clear DF for host ABI
        if(mprotect(p,4096,PROT_READ|PROT_EXEC)) return 1;
        for(unsigned j=0;j<sizeof(values)/sizeof(values[0]);j++) for(unsigned f=0;f<4;f++) {
            uint64_t flags=2|(f&1?0x8d5:0)|(f&2?0x400:0);
            uint64_t row[]={width,form,immediates[k],values[j],flags,native(values[j],flags)&0x8c5};
            if(fwrite(row,sizeof(row),1,out)!=1) return 1;
        }
        if(mprotect(p,4096,PROT_READ|PROT_WRITE)) return 1;
    }
    for(unsigned cc=0;cc<16;cc++) {
        size_t n=0;emit(p,&n,0x9d56,2);emit(p,&n,0x0f,1);emit(p,&n,0x90+cc,1);emit(p,&n,0xc0,1);emit(p,&n,0xc3c0b60f,4);
        if(mprotect(p,4096,PROT_READ|PROT_EXEC)) return 1;
        for(unsigned f=0;f<32;f++) {
            uint64_t flags=2|(f&1)|((f&2)*2)|((f&4)*16)|((f&8)*16)|((f&16)*128);
            uint64_t row[]={1,2,cc,0,flags,native(0,flags)};
            if(fwrite(row,sizeof(row),1,out)!=1) return 1;
        }
        if(mprotect(p,4096,PROT_READ|PROT_WRITE)) return 1;
    }
    return fclose(out)!=0;
}
