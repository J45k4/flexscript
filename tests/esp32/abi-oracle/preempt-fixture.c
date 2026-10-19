/* Independent GNU ABI/state oracle; not production scheduler code. */
typedef unsigned int u32;
extern u32 c_preempt_loop(volatile u32 *state,u32 slot,u32 marker);
#define SET_FP(n) __asm__ volatile("wfr f" #n ",%0"::"a"(marker):"f" #n)
#define CHECK_FP(n) do {u32 got;__asm__ volatile("rfr %0,f" #n:"=a"(got));if(got!=marker)return 20+(n);}while(0)
__attribute__((noinline)) u32 c_preempt_busy(volatile u32 *state,u32 slot,u32 depth,u32 marker) {
    volatile u32 guard[12];for(u32 i=0;i<12;i++)guard[i]=(depth+1)*0x13579u+i*0x2468u+marker;
    u32 result;
    if(depth)result=c_preempt_busy(state,slot,depth-1,marker);
    else {
        u32 thread=0x12340000u+slot,control=slot+1,status=(slot+1)<<7,expected_control,expected_status;
        __asm__ volatile("wur.threadptr %0\nwur.fcr %1\nwur.fsr %2"::"a"(thread),"a"(control),"a"(status));
        __asm__ volatile("rur.fcr %0\nrur.fsr %1":"=a"(expected_control),"=a"(expected_status));
        SET_FP(0);SET_FP(1);SET_FP(2);SET_FP(3);SET_FP(4);SET_FP(5);SET_FP(6);SET_FP(7);
        SET_FP(8);SET_FP(9);SET_FP(10);SET_FP(11);SET_FP(12);SET_FP(13);SET_FP(14);SET_FP(15);
        result=c_preempt_loop(state,slot,marker);
        CHECK_FP(0);CHECK_FP(1);CHECK_FP(2);CHECK_FP(3);CHECK_FP(4);CHECK_FP(5);CHECK_FP(6);CHECK_FP(7);
        CHECK_FP(8);CHECK_FP(9);CHECK_FP(10);CHECK_FP(11);CHECK_FP(12);CHECK_FP(13);CHECK_FP(14);CHECK_FP(15);
        u32 got_thread,got_control,got_status;__asm__ volatile("rur.threadptr %0\nrur.fcr %1\nrur.fsr %2":"=a"(got_thread),"=a"(got_control),"=a"(got_status));
        if(got_thread!=thread || got_control!=expected_control || got_status!=expected_status)return 40;
    }
    for(u32 i=0;i<12;i++)if(guard[i]!=(depth+1)*0x13579u+i*0x2468u+marker)return 100+depth;
    return result;
}

u32 c_preempt_irq_clobber(void) {
    u32 marker=0x3f777777,thread=0x24681357,control=3,status=0x80;
    SET_FP(0);SET_FP(1);SET_FP(2);SET_FP(3);SET_FP(4);SET_FP(5);SET_FP(6);SET_FP(7);
    SET_FP(8);SET_FP(9);SET_FP(10);SET_FP(11);SET_FP(12);SET_FP(13);SET_FP(14);SET_FP(15);
    __asm__ volatile("wur.threadptr %0\nwur.fcr %1\nwur.fsr %2"::"a"(thread),"a"(control),"a"(status));return 1;
}
