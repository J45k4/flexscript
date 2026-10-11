#define _GNU_SOURCE
#include <stdint.h>
#include <signal.h>
#include <setjmp.h>
#include <sys/mman.h>
#include <unistd.h>
#include <stdio.h>

static void rotate(unsigned width, unsigned right, unsigned count, uint64_t initial, uint64_t *a, uint64_t *flags) {
    uint64_t value=*a, f;
#define ROTATE(text) __asm__ volatile("pushq %3; popfq; " text "; pushfq; popq %1" : "+a"(value), "=r"(f) : "c"((uint64_t)count), "r"(initial) : "cc")
    if (width==1) {if (right) ROTATE("rcrb %%cl, %%al"); else ROTATE("rclb %%cl, %%al");}
    else if (width==2) {if (right) ROTATE("rcrw %%cl, %%ax"); else ROTATE("rclw %%cl, %%ax");}
    else if (width==4) {if (right) ROTATE("rcrl %%cl, %%eax"); else ROTATE("rcll %%cl, %%eax");}
    else {if (right) ROTATE("rcrq %%cl, %%rax"); else ROTATE("rclq %%cl, %%rax");}
#undef ROTATE
    *a=value; *flags=f;
}
static sigjmp_buf fault_jump;
static void caught_fault(int signal_number) { (void)signal_number; siglongjmp(fault_jump,1); }
static int memory_permissions(void) {
    long size=sysconf(_SC_PAGESIZE);
    if (size<1) return 1;
    void *page=mmap(NULL,(size_t)size,PROT_READ|PROT_WRITE,MAP_PRIVATE|MAP_ANONYMOUS,-1,0);
    if (page==MAP_FAILED) return 1;
    *(uint64_t *)page=7;
    if (mprotect(page,(size_t)size,PROT_READ)) return 1;
    struct sigaction action={0}, previous;
    action.sa_handler=caught_fault;
    sigemptyset(&action.sa_mask);
    if (sigaction(SIGSEGV,&action,&previous)) return 1;
    volatile int ok=1;
    for (volatile unsigned count=0;count<2;count++) {
        if (!sigsetjmp(fault_jump,1)) {
            __asm__ volatile("rcrq %%cl,(%0)" : : "r"(page),"c"((uint64_t)count) : "cc","memory");
            ok=0;
        }
    }
    if (!sigsetjmp(fault_jump,1)) {
        __asm__ volatile("rclb $9,(%0)" : : "r"(page) : "cc","memory");
        ok=0;
    }
    if (*(uint64_t *)page!=7) ok=0;
    sigaction(SIGSEGV,&previous,NULL);
    munmap(page,(size_t)size);
    return !ok;
}
int main(int argc,char **argv) {
    if (memory_permissions()) return 1;
    if (argc!=2) return 1;
    FILE *file=fopen(argv[1],"wb");if (!file) return 1;
    const uint64_t values[]={0,1,UINT64_MAX,0x8000000000000000ull,0x1234567887654321ull,0xaaaaaaaa55555555ull,0x8000800080000080ull,0x7fff7fff7fff007full};
    const unsigned counts[]={0,1,2,7,8,9,15,16,17,31,32,33,63,64,65,127,128,255};
    for (unsigned width=1;width<=8;width*=2) for (unsigned right=0;right<2;right++)
      for (unsigned carry=0;carry<2;carry++) for (unsigned v=0;v<8;v++) for (unsigned n=0;n<18;n++) {
        uint64_t row[8]={width,right,counts[n],values[v],0xad6|carry,values[v],0,0};
        rotate(width,right,counts[n],row[4],&row[5],&row[6]);
        if (fwrite(row,sizeof(row),1,file)!=1) return 1;
      }
    return fclose(file)!=0;
}
