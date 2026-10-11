#include <stdint.h>
#include <stdio.h>

static void evaluate(unsigned index, const uint64_t in[2], uint32_t value,
                     uint32_t *extracted, uint64_t out[2]) {
#define CASE(n) case n: \
    __asm__ volatile("movdqu %1, %%xmm15; pextrw $" #n ", %%xmm15, %0" \
        : "=r"(*extracted) : "m"(*(const uint64_t (*)[2])in) : "xmm15"); \
    __asm__ volatile("movdqu %1, %%xmm15; pinsrw $" #n ", %2, %%xmm15; movdqu %%xmm15, %0" \
        : "=m"(*(uint64_t (*)[2])out) : "m"(*(const uint64_t (*)[2])in), "r"(value) : "xmm15"); break
    switch (index & 7) { CASE(0); CASE(1); CASE(2); CASE(3); CASE(4); CASE(5); CASE(6); CASE(7); }
#undef CASE
}
int main(int argc, char **argv) {
    if (argc != 2) return 2;
    FILE *file = fopen(argv[1], "wb"); if (!file) return 2;
    for (unsigned i = 0; i < 256; ++i) {
        uint64_t row[8] = {i, 0x8000ffff12340000ull ^ ((uint64_t)i << 40),
                          0xdeadbeefabcd6789ull ^ ((uint64_t)i << 24),
                          0xface0000u | ((i * 983u) & 65535u), 0, 0, 0, 0};
        uint32_t extracted = 0;
        evaluate(i, row + 1, (uint32_t)row[3], &extracted, row + 5);
        row[4] = extracted;
        if (fwrite(row, sizeof row, 1, file) != 1) return 1;
    }
    return fclose(file) != 0;
}
