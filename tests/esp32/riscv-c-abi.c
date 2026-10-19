/* Independent ILP32 producer/consumer. No runtime or SDK substitutes. */
typedef unsigned int u32;
typedef unsigned long long u64;
typedef u64 (*callback8)(u32,u32,u32,u32,u32,u32,u32,u32);
extern volatile u64 rv_calls, rv_cookie;
extern u64 rv_callback(u32,u32,u32,u32,u32,u32,u32,u32);
extern u64 rv_iram_callback(u32,u32,u32,u32,u32,u32,u32,u32);
extern u64 rv_c_register_probe(callback8);
static volatile u32 bss[32];
static const u32 words[8]={0,1,0x80000000,0xffffffff,0x23456789,0xdeadbeef,0xabcdef01,0x87654321};
static volatile u32 initialized=0x98765432;
__attribute__((noinline)) u64 rv_c_mix8(u32 a,u32 b,u32 c,u32 d,u32 e,u32 f,u32 g,u32 h) {
    u32 stack;__asm__ volatile("mv %0,sp":"=r"(stack));
    if(stack&15) return 0xbad0000000000003ULL;
    return ((u64)a+((u64)b<<32))^((u64)c*0x100000003ULL)^((u64)d<<17)^((u64)e<<29)^((u64)f*19)^((u64)g<<7)^h;
}
u64 rv_c_driver(u32 a,u32 b,u32 c,u32 d,u32 e,u32 f,u32 g,u32 h) {
    u32 stack;__asm__ volatile("mv %0,sp":"=r"(stack));if(stack&15)return 0xbad0000000000005ULL;
    volatile u32 scratch[192];for(u32 i=0;i<192;i++)scratch[i]=i^b;
    u64 result=rv_callback(a-1,b,c,d,e,f,g,h);
    for(u32 i=0;i<192;i++)if(scratch[i]!=(i^b))return 0xbad0000000000004ULL;
    return result;
}
static u64 expected(u32 a,u32 b,u32 c,u32 d,u32 e,u32 f,u32 g,u32 h) {
    /* Deliberately separate arithmetic from rv_c_mix8's implementation. */
    u64 v=(u64)b*0x100000000ULL+a;
    v^=(u64)c+((u64)c*2)+((u64)c*0x100000000ULL);
    v^=(u64)d*131072;v^=(u64)e*536870912;v^=(u64)f*19;v^=(u64)g*128;v^=h;
    if(a && a<5)v^=expected(a-1,b,c,d,e,f,g,h);
    return v;
}
u32 rv_c_acceptance(callback8 cb,callback8 iram,u32 low,u32 high,u32 e,u32 f,u32 g,u32 h) {
    u32 stack;__asm__ volatile("mv %0,sp":"=r"(stack));if(stack&15)return 103;
    if(low!=0x9abcdef0 || high!=0x12345678 || e!=0xffffffff || f!=0x80000000 || g!=0xdeadbeef || h!=0xabcdef01)return 100;
    if(rv_cookie!=0x123456789abcdef0ULL || rv_calls || initialized!=0x98765432)return 101;
    for(u32 i=0;i<32;i++)if(bss[i])return 102;
    u32 calls=0;
    for(u32 n=0;n<5;n++) {
        u32 b=words[2],c=words[3],d=words[4],ee=words[5],ff=words[6],gg=words[7],hh=0xfedcba98;
        u64 want=expected(n,b,c,d,ee,ff,gg,hh);
        if(cb(n,b,c,d,ee,ff,gg,hh)!=want)return 110+n;calls+=n+1;
        if(rv_callback(n,b,c,d,ee,ff,gg,hh)!=want)return 120+n;calls+=n+1;
        if(iram(n,b,c,d,ee,ff,gg,hh)!=(want^0x1020304050607080ULL))return 130+n;calls+=n+1;
        if(rv_iram_callback(n,b,c,d,ee,ff,gg,hh)!=(want^0x1020304050607080ULL))return 140+n;calls+=n+1;
        if(rv_calls!=calls)return 150+n;
        bss[n]=n+1;
    }
    if(rv_c_register_probe(cb)!=expected(0,0xffffffff,0x80000000,0xdeadbeef,0x23456789,0xabcdef01,0x87654321,0xfedcba98))return 160;
    if(rv_calls!=calls+1)return 161;
    return 0;
}
u32 rv_c_enable(void) {__asm__ volatile("csrsi mstatus,8" ::: "memory");return 0;}
