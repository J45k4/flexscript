// Capacity boundaries and AAPCS64 preservation across checked/fast exits.
#include "../../platform/android/jit-host.h"
extern long arm64_jit_compile(long, long, long, long, long, long);
extern long jit_check_abi(long, long *);
static unsigned char code[4096], scratch[1024];
static const long ir[] = {18, 1, 3, 0, 2, 0, 1, 0, 7, 47, 5, 16, 9, 0};
long runner_main(void) {
    long needed = arm64_jit_compile((long)ir, (long)sizeof(ir), (long)code, (long)sizeof(code), (long)scratch, (long)sizeof(scratch));
    if (needed <= 0 || needed >= (long)sizeof(code) - 4) return 1;
    for (long capacity = 0; capacity < needed + 4; capacity++) {
        for (long i = 0; i < (long)sizeof(code); i++) code[i] = 0xa5;
        long size = arm64_jit_compile((long)ir, (long)sizeof(ir), (long)code, capacity, (long)scratch, (long)sizeof(scratch));
        if (size != (capacity < needed ? -3 : needed)) return 2;
        for (long i = capacity; i < (long)sizeof(code); i++) if (code[i] != 0xa5) return 3;
    }
    for (long bytes = 0; bytes < (long)sizeof(ir) * 3 / 2; bytes++) {
        for (long i = 0; i < (long)sizeof(scratch); i++) scratch[i] = 0xa5;
        if (arm64_jit_compile((long)ir, (long)sizeof(ir), (long)code, (long)sizeof(code), (long)scratch, bytes) != -3) return 4;
        for (long i = 0; i < (long)sizeof(scratch); i++) if (scratch[i] != 0xa5) return 5;
    }
    if (arm64_jit_compile((long)ir, (long)sizeof(ir), (long)code, (long)sizeof(code), (long)scratch, (long)sizeof(ir) * 3 / 2) != needed) return 6;
    long handle[2] = {0, 0}, initial = 42;
    if (flex_jit_publish(code, needed, handle)) return 7;
    for (long fuel = 0; fuel <= 10; fuel++) {
        long ctx[9] = {(long)&initial, fuel, 0, 0, 0, 0, 0, 0, 0};
        if (jit_check_abi(handle[0], ctx)) return 8;
        if (ctx[2] != (fuel < 4 ? 1 : 2) || ctx[1] != (fuel < 4 ? 0 : fuel - 4)) return 9;
    }
    flex_jit_release(handle);
    const long success[] = {18, 1, 3, 0, 9, 0};
    needed = arm64_jit_compile((long)success, sizeof(success), (long)code, sizeof(code), (long)scratch, sizeof(scratch));
    if (needed <= 0 || flex_jit_publish(code, needed, handle)) return 10;
    for (long fuel = 0; fuel <= 3; fuel++) {
        long ctx[9] = {(long)&initial, fuel, 0, 0, 0, 0, 0, 0, 0};
        if (jit_check_abi(handle[0], ctx)) return 11;
        if (ctx[2] != (fuel < 2 ? 1 : 0) || ctx[1] != (fuel < 2 ? 0 : fuel - 2)) return 12;
    }
    flex_jit_release(handle);
    // A backward conditional site counts even when it does not take the branch.
    // Keep heap metadata live in caller-saved registers across the clock SVC.
    const long clock_ir[] = {18, 1, 3, 0, 11, 16, 5, 16, 9, 0};
    long heap[6] = {0, 0, 7, 0, 0, 0};
    needed = arm64_jit_compile((long)clock_ir, sizeof(clock_ir), (long)code, sizeof(code), (long)scratch, sizeof(scratch));
    if (needed <= 0 || flex_jit_publish(code, needed, handle)) return 13;
    const long deadlines[3] = {0, 999999999999999999L, 1};
    for (long i = 0; i < 3; i++) {
        long ctx[9] = {(long)&initial, 100, 0, 1023, deadlines[i], 0, 0, (long)heap, sizeof(heap)};
        if (jit_check_abi(handle[0], ctx)) return 14;
        if (ctx[2] != (i == 2 ? 8 : 0) || ctx[1] != (i == 2 ? 98 : 96) || ctx[3] != 1024) return 15;
        ctx[1] = 100; ctx[2] = 0; ctx[3] = 1023;
        if (flex_jit_call(handle, ctx) != (i == 2 ? 0 : 7)) return 16;
    }
    flex_jit_release(handle);
    // Put a tiny output buffer immediately before an inaccessible page. This
    // also catches patchers that read beyond a failed clock/batch emission.
    const long guarded[] = {18, 2, 3, 1, 2, 0, 3, 0, 7, 60, 11, 192,
                            3, 1, 2, 0, 1, 1, 7, 43, 4, 1, 10, 16, 3, 1, 9, 0};
    needed = arm64_jit_compile((long)guarded, sizeof(guarded), (long)code, sizeof(code), (long)scratch, sizeof(scratch));
    if (needed <= 0 || needed >= (long)sizeof(code)) return 17;
    long mapping = flex_jit_syscall(222, 0, 131072, 3, 34, -1, 0);
    if (mapping < 0 || flex_jit_syscall(226, mapping + 65536, 65536, 0, 0, 0, 0)) return 18;
    for (long capacity = 0; capacity <= needed; capacity++) {
        long size = arm64_jit_compile((long)guarded, sizeof(guarded), mapping + 65536 - capacity,
                                     capacity, (long)scratch, sizeof(scratch));
        if (size != (capacity < needed ? -3 : needed)) return 19;
    }
    if (flex_jit_syscall(215, mapping, 131072, 0, 0, 0, 0)) return 20;
    needed = arm64_jit_compile((long)guarded, sizeof(guarded), (long)code, sizeof(code), (long)scratch, sizeof(scratch));
    if (needed <= 0 || flex_jit_publish(code, needed, handle)) return 21;
    // Force clock expiry in each of the four unrolled bodies, including their
    // prepaid future headers/iterations. Live clocks preserve all saved state.
    long loop_locals[2] = {10, 0};
    for (long phase = 0; phase < 4; phase++) {
        for (long mode = 0; mode < 3; mode++) {
            long ctx[9] = {(long)loop_locals, 10000, 0, 1023 - phase, deadlines[mode], 0, 0, 0, 0};
            if (jit_check_abi(handle[0], ctx)) return 22;
            long fuel = mode == 2 ? 9989 - phase * 11 : 9883;
            long edges = mode == 2 ? 1024 : 1033 - phase;
            if (ctx[1] != fuel || ctx[2] != (mode == 2 ? 8 : 0) || ctx[3] != edges) return 23;
            ctx[1] = 10000; ctx[2] = 0; ctx[3] = 1023 - phase;
            if (flex_jit_call(handle, ctx) != (mode == 2 ? 0 : 10)) return 24;
        }
    }
    flex_jit_release(handle);
    return 0;
}
