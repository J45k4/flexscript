/* Independent GNU Xtensa ABI oracle; never linked into production firmware. */
typedef unsigned int u32;
typedef unsigned long long u64;
typedef u64 (*callback8)(u32,u32,u32,u32,u32,u32,u32,u32);
__attribute__((noinline)) u64 c_walk(u32 depth, callback8 cb) {
    volatile u32 saved[12];
    for (u32 i=0;i<12;i++) saved[i]=(depth+1)^(0x1234u*i);
    u64 r;
    if (depth) r=c_walk(depth-1,cb);
    else r=cb(11,22,33,44,55,66,0x89abcdefu,0xfedcba98u);
    for (u32 i=1;i<12;i++) if(saved[i]!=((depth+1)^(0x1234u*i))) return 0;
    return r+saved[0];
}
__attribute__((noinline)) u32 c_sum8(u32 a,u32 b,u32 c,u32 d,u32 e,u32 f,u32 g,u32 h) {return a+3*b+5*c+7*d+11*e+13*f+17*g+19*h;}
__attribute__((noinline)) u32 c_wait(u32 cycles) {
    u32 start,now;__asm__ volatile("rsr %0,ccount":"=a"(start));
    do {__asm__ volatile("rsr %0,ccount":"=a"(now));}while((u32)(now-start)<cycles);
    return 0x13572468;
}
__attribute__((noinline)) u32 c_set_fpu(u32 marker) {
    __asm__ volatile("wfr f0,%0\nwfr f15,%0"::"a"(marker):"f0","f15");return marker;
}
__attribute__((noinline)) u32 c_read_fpu(void) {u32 x;__asm__ volatile("rfr %0,f0":"=a"(x));return x;}
__attribute__((noinline)) u32 c_coop(u32 depth,callback8 cb,u32 marker) {
    volatile u32 canary=depth^0xabc123;
    u32 r;
    if(depth) r=c_coop(depth-1,cb,marker);
    else {
        c_set_fpu(marker);r=(u32)cb(1,2,3,4,5,6,7,8);
        u32 x,y;__asm__ volatile("rfr %0,f0\nrfr %1,f15":"=a"(x),"=a"(y));
        if(x!=marker || y!=marker || r!=0x98765432u) return 0;
        r=17;
    }
    if(canary!=(depth^0xabc123))return 0;
    return r+depth;
}

volatile u32 c_uninitialized;
u32 c_bss_probe(void) { if(c_uninitialized) return 0; c_uninitialized=0x56789abc; return c_uninitialized; }
u32 c_set_thread(u32 value) { __asm__ volatile("wur.threadptr %0"::"a"(value)); return value; }
u32 c_read_thread(void) {u32 x;__asm__ volatile("rur.threadptr %0":"=a"(x));return x;}
u32 c_read_vecbase(void) {u32 x;__asm__ volatile("rsr.vecbase %0":"=a"(x));return x;}
u32 c_stack_alignment(void) {u32 sp;__asm__ volatile("mov %0,a1":"=a"(sp));return sp&15;}

/* IRQ changes are observable across ABI boundaries, not callee-saved PS. */
u32 c_irq_after_callback(u32 address) {
    typedef u32 (*callback_t)(u32,u32,u32,u32,u32,u32,u32,u32);
    ((callback_t)address)(0,0,0,0,0,0,0,0);
    u32 ps; __asm__ volatile("rsr.ps %0":"=a"(ps)); return ps&15;
}
