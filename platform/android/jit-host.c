/* Android/Linux AArch64 executable-memory adapter. All code generation belongs
 * to Flexscript; this host boundary publishes, synchronizes and calls code.
 * Code mappings are writable only during publication, then permanently RX.
 */
_Static_assert(sizeof(long) == 8, "AArch64 LP64 required");
#include "jit-host.h"
long flex_jit_syscall(long number, long a, long b, long c, long d, long e, long f) {
    register long x0 __asm__("x0") = a;
    register long x1 __asm__("x1") = b;
    register long x2 __asm__("x2") = c;
    register long x3 __asm__("x3") = d;
    register long x4 __asm__("x4") = e;
    register long x5 __asm__("x5") = f;
    register long x8 __asm__("x8") = number;
    __asm__ volatile("svc #0" : "+r"(x0) : "r"(x1), "r"(x2), "r"(x3), "r"(x4), "r"(x5), "r"(x8) : "memory", "cc");
    return x0;
}
static void jit_sync_cache(char *start, char *end) {
    unsigned long ctr;
    __asm__ volatile("mrs %0, ctr_el0" : "=r"(ctr));
    if (!(ctr & (1UL << 28))) {
        unsigned long line = 4UL << (ctr & 15);
        for (unsigned long p = (unsigned long)start & ~(line - 1); p < (unsigned long)end; p += line)
            __asm__ volatile("dc cvau, %0" : : "r"(p) : "memory");
    }
    __asm__ volatile("dsb ish" : : : "memory");
    if (!(ctr & (1UL << 29))) {
        unsigned long line = 4UL << ((ctr >> 16) & 15);
        for (unsigned long p = (unsigned long)start & ~(line - 1); p < (unsigned long)end; p += line)
            __asm__ volatile("ic ivau, %0" : : "r"(p) : "memory");
        __asm__ volatile("dsb ish" : : : "memory");
    }
    __asm__ volatile("isb" : : : "memory");
}
long flex_jit_publish(const unsigned char *source, long size, long *handle) {
    if (!source || !handle || size <= 0 || size > 1048576 || size % 4) return -22;
    // A multiple of 64 KiB works on 4-, 16- and 64-KiB page-size kernels.
    long bytes = (size + 65535) & -65536;
    long code = flex_jit_syscall(222, 0, bytes, 3, 34, -1, 0);
    if (code < 0) return code;
    for (long i = 0; i < size; i++) ((unsigned char *)code)[i] = source[i];
    long result = flex_jit_syscall(226, code, bytes, 5, 0, 0, 0);
    if (result < 0) { flex_jit_syscall(215, code, bytes, 0, 0, 0, 0); return result; }
    jit_sync_cache((char *)code, (char *)code + size);
    handle[0] = code; handle[1] = bytes;
    return 0;
}
long flex_jit_call(const long *handle, long *context) {
    return ((long (*)(long *))handle[0])(context);
}
long flex_jit_release(long *handle) {
    if (!handle || !handle[0]) return 0;
    long result = flex_jit_syscall(215, handle[0], handle[1], 0, 0, 0, 0);
    if (!result) { handle[0] = 0; handle[1] = 0; }
    return result;
}
