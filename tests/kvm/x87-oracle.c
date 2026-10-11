#include <stdint.h>
#include <stdio.h>
#include <string.h>

static void evaluate(unsigned op, uint64_t a, uint64_t b, uint16_t cw,
                     uint64_t *result, uint64_t *status, uint64_t *flags) {
    double x, y, out;
    uint16_t sw;
    uint64_t f;
    memcpy(&x, &a, 8);
    memcpy(&y, &b, 8);
    __asm__ volatile("fninit; fldcw %0; fldl %1; fldl %2"
                     : : "m"(cw), "m"(y), "m"(x) : "st", "st(1)");
#define OP(insn) __asm__ volatile(insn "; pushfq; popq %0" : "=r"(f) : : "cc", "st")
    switch (op) {
    case 0: OP("fadd %%st(1), %%st"); break;
    case 1: OP("fmul %%st(1), %%st"); break;
    case 2: OP("fsub %%st(1), %%st"); break;
    case 3: OP("fdiv %%st(1), %%st"); break;
    case 4: OP("fcomi %%st(1), %%st"); break;
    default: OP("fucomi %%st(1), %%st"); break;
    }
#undef OP
    __asm__ volatile("fstpl %0; fnstsw %1; fninit" : "=m"(out), "=m"(sw) : : "st");
    memcpy(result, &out, 8);
    *status = sw;
    *flags = f & 0x8d5;
}

int main(int argc, char **argv) {
    if (argc != 2) return 2;
    FILE *file = fopen(argv[1], "wb");
    if (!file) return 2;
    const uint64_t values[] = {
        0, 0x8000000000000000ull, 0x3ff0000000000000ull,
        0xbff0000000000000ull, 0x7fefffffffffffffull,
        0x0010000000000000ull, 1, 0x7ff8000000000123ull,
        0x7ff0000000000000ull, 0x3fb999999999999aull
    };
    for (unsigned rounding = 0; rounding < 4; ++rounding)
        for (unsigned op = 0; op < 6; ++op)
            for (unsigned a = 0; a < 10; ++a)
                for (unsigned b = 0; b < 10; ++b) {
                    uint64_t row[8] = {op, values[a], values[b], 0x37f | (rounding << 10), 0, 0, 0, 0};
                    evaluate(op, row[1], row[2], row[3], &row[4], &row[5], &row[6]);
                    if (fwrite(row, sizeof(row), 1, file) != 1) return 1;
                }
    return fclose(file) != 0;
}
