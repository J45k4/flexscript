/* Static TLS consumer. LLVM supplies TLS relocations; Flexscript owns startup. */
typedef unsigned int u32;typedef unsigned long long u64;typedef unsigned long uptr;
#ifndef TLS_ALIGNMENT
#define TLS_ALIGNMENT 256
#endif
__thread volatile u32 tls_first=0x12345678;
__thread volatile u64 tls_wide=0x8877665544332211ULL;
__thread volatile u32 tls_zero;
__attribute__((aligned(TLS_ALIGNMENT))) __thread volatile unsigned char tls_aligned[13]={1,2,3,4};
__attribute__((aligned(128))) __thread volatile unsigned char tls_bss[33];
static uptr current_tp(void){uptr tp;__asm__ volatile("mv %0,tp":"=r"(tp));return tp;}
u32 tls_validate_initial(void){if(!current_tp()||(current_tp()&(TLS_ALIGNMENT-1)))return 1;if(tls_first!=0x12345678||tls_wide!=0x8877665544332211ULL||tls_zero)return 2;if(((uptr)tls_aligned&(TLS_ALIGNMENT-1))||((uptr)tls_bss&127))return 3;for(u32 i=0;i<13;i++)if(tls_aligned[i]!=(i<4?i+1:0))return 4;for(u32 i=0;i<33;i++)if(tls_bss[i])return 5;return 0;}
u32 tls_set(u32 value){tls_first=value;tls_wide=0x1122334400000000ULL|value;tls_zero=value^0xdeadbeef;for(u32 i=0;i<13;i++)tls_aligned[i]=value+i;for(u32 i=0;i<33;i++)tls_bss[i]=value^i;return 0;}
u32 tls_validate_set(u32 value){if(tls_first!=value||tls_wide!=(0x1122334400000000ULL|value)||tls_zero!=(value^0xdeadbeef))return 1;for(u32 i=0;i<13;i++)if(tls_aligned[i]!=(unsigned char)(value+i))return 2;for(u32 i=0;i<33;i++)if(tls_bss[i]!=(unsigned char)(value^i))return 3;return 0;}
u32 tls_address(void){return current_tp();}
u32 tls_stack_probe(void){volatile unsigned char buffer[3000];for(u32 i=0;i<3000;i++)buffer[i]=i;for(u32 i=0;i<3000;i++)if(buffer[i]!=(unsigned char)i)return 1;return 0;}
