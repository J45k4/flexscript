#include "../../platform/android/jit-host.h"
static unsigned char requests[16777216];
static long results[8192 * 10 + 5];
long runner_main(void) {
    long size = 0;
    while (size < (long)sizeof(requests)) {
        long n = flex_jit_syscall(63, 0, (long)(requests + size), sizeof(requests) - size, 0, 0, 0);
        if (n < 0) return 90;
        if (!n) break;
        size += n;
    }
    long summary = flex_jit_cases(requests, size, results, sizeof(results));
    if (summary < 0) return 91;
    long bytes = 40 + results[0] * 80, sent = 0;
    while (sent < bytes) {
        long n = flex_jit_syscall(64, 1, (long)((unsigned char *)results + sent), bytes - sent, 0, 0, 0);
        if (n <= 0) return 92;
        sent += n;
    }
    flex_jit_reset();
    return results[0] == results[1] ? 0 : 1;
}
