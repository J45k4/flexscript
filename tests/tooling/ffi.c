#include <stdint.h>
#include <stdlib.h>
static long state;
long six(long a,long b,long c,long d,long e,long f){return a+2*b+3*c+4*d+5*e+6*f;}
int negative(void){return -17;}
unsigned high(void){return 0xf1234567U;}
uint64_t word(void){return UINT64_C(0xf123456789abcdef);}
void set(long n){state=n;}
long get(void){return state;}
void* same(void* p){return p;}
long aligned(void){uintptr_t p;__asm__("mov %%rsp,%0":"=r"(p));return (p&15)==8;}
