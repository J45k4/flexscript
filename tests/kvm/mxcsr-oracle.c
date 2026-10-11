#include <stdint.h>
#include <stdio.h>

int main(int argc, char **argv) {
    if (argc != 2) return 2;
    FILE *file = fopen(argv[1], "wb");
    if (!file) return 2;
    _Alignas(16) unsigned char state[512] = {0};
    __asm__ volatile("fxsave64 %0" : "=m"(state));
    uint32_t mask = *(uint32_t *)(state + 28);
    if (!mask) mask = 0xffbf;
    uint64_t header = mask;
    if (fwrite(&header, sizeof header, 1, file) != 1) return 1;
    for (unsigned mode = 0; mode < 4; ++mode) {
        uint32_t control = 0x1f80 | ((mode & 1) ? (mask & 0x40) : 0)
                                 | ((mode & 2) ? 0x8000 : 0);
        uint32_t input = 1, zero = 0, normal = 0x00800000, half = 0x3f000000;
        uint32_t sum, product, after_sum, after_product;
        __asm__ volatile("ldmxcsr %4; movss %5, %%xmm0; addss %6, %%xmm0; movss %%xmm0, %0; stmxcsr %1;"
                         "ldmxcsr %4; movss %7, %%xmm0; mulss %8, %%xmm0; movss %%xmm0, %2; stmxcsr %3"
            : "=m"(sum), "=m"(after_sum), "=m"(product), "=m"(after_product)
            : "m"(control), "m"(input), "m"(zero), "m"(normal), "m"(half) : "xmm0", "memory");
        uint64_t row[5] = {control, sum, after_sum, product, after_product};
        if (fwrite(row, sizeof row, 1, file) != 1) return 1;
    }
    __asm__ volatile("fxrstor64 %0" : : "m"(state) : "memory");
    return fclose(file) != 0;
}
