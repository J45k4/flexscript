typedef unsigned int u32;
typedef unsigned long long u64;
typedef u64 (*callback8)(u32,u32,u32,u32,u32,u32,u32,u32);
extern u64 ctx_c_probe(callback8,u32,u32);
__attribute__((noinline)) u64 ctx_c_nested(callback8 cb,u32 depth,u32 cookie) {
    volatile u32 saved[12];for(u32 i=0;i<12;i++)saved[i]=i^cookie^depth;
    u64 value=0;
    if(depth)value=ctx_c_nested(cb,depth-1,cookie);
    else for(u32 i=0;i<3;i++)value+=cb(1,2,3,4,5,6,7,8);
    for(u32 i=0;i<12;i++)if(saved[i]!=(i^cookie^depth))return 0xbad0000000000001ULL;
    return value+(u64)depth*cookie+saved[depth%12];
}
u32 ctx_c_check(callback8 cb,u32 depth,u32 cookie) {
    u64 expected=0x369d0369d0369cd0ULL;
    for(u32 i=0;i<=depth;i++)expected+=(u64)i*cookie+(i%12^cookie^i);
    return ctx_c_probe(cb,depth,cookie)!=expected;
}
