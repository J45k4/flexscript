/* Freestanding ARM64 test driver for the exact Android library engine. */
extern long collie_call(long, const char *, long, char *, long, const char *);
static char input[8388609], output[8388609];
static long call(long n, long a, long b, long c) {
    register long x8 __asm__("x8") = n, x0 __asm__("x0") = a, x1 __asm__("x1") = b,
                     x2 __asm__("x2") = c;
    __asm__ volatile("svc #0" : "+r"(x0) : "r"(x8), "r"(x1), "r"(x2) : "memory");
    return x0;
}
void start_c(long *sp) {
    long argc = *sp;
    char **argv = (char **)(sp + 1);
    long op = 3;
    if (argc > 1)
        op = argv[1][0] - '0';
    long size = 0;
    while (size < 8388608) {
        long n = call(63, 0, (long)input + size, 8388608 - size);
        if (n <= 0)
            break;
        size += n;
    }
    long n = collie_call(op, input, size, output, 8388608,
                         argc > 2 ? argv[2] : "/tmp/collie-android-test");
    if (n > 0)
        call(64, 1, (long)output, n);
    call(93, n < 0 ? 1 : 0, 0, 0);
    for (;;) {
    }
}
__asm__(".text\n.global _start\n_start:\nmov x0,sp\nbl start_c\n");
