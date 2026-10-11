#define _GNU_SOURCE
#include <emmintrin.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>

int main(int argc, char **argv) {
    if (argc != 2) return 2;
    FILE *file = fopen(argv[1], "wb");
    if (!file) return 2;
    unsigned char *code = mmap(NULL, 16384, PROT_READ | PROT_WRITE,
                               MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (code == MAP_FAILED) return 2;
    /* Fixed trusted PSHUFD templates; each differs only by its imm8. */
    const unsigned char body[] = {0xf3,0x0f,0x6f,0x0e,0x66,0x0f,0x70,0xc1,0,
                                   0xf3,0x0f,0x7f,0x07,0xc3};
    const unsigned char shift_body[] = {0xf3,0x0f,0x6f,0x06,0x66,0x0f,0x73,0xd8,0,
                                      0xf3,0x0f,0x7f,0x07,0xc3};
    for (unsigned i = 0; i < 256; ++i) {
        memcpy(code + i * 32, body, sizeof(body));
        code[i * 32 + 8] = i;
        memcpy(code + 8192 + i * 32, shift_body, sizeof(shift_body));
        code[8192 + i * 32 + 8] = i;
    }
    if (mprotect(code, 16384, PROT_READ | PROT_EXEC)) return 2;
    const uint64_t values[] = {0, UINT64_MAX, 0x8000800080008000ull,
        0x7ff8000012345678ull, 0x0102030405060708ull, 0xff00ff0000ff00ffull,
        0x8000000000000001ull, 0x123456789abcdef0ull};
    for (unsigned op = 0; op < 6; ++op) {
        unsigned immediates = op == 3 || op == 5 ? 256 : 1;
        for (unsigned imm = 0; imm < immediates; ++imm)
        /* PSHUFD reads only b, so varying the overwritten a is redundant. */
        for (unsigned i = 0; i < (op == 3 || op == 5 ? 1u : 8u); ++i) for (unsigned j = 0; j < 8; ++j) {
            uint64_t row[9] = {op, imm, values[i], ~values[i], values[j],
                               values[(j + 3) % 8], 0, 0, 0};
            __m128i a = _mm_loadu_si128((const __m128i *)(row + 2));
            __m128i b = _mm_loadu_si128((const __m128i *)(row + 4));
            __m128i out = a;
            if (op == 0) out = _mm_xor_si128(a, b);
            if (op == 1) out = _mm_cmpeq_epi8(a, b);
            if (op == 2) row[8] = (unsigned)_mm_movemask_epi8(b);
            if (op == 4) out = _mm_add_epi64(a, b);
            _mm_storeu_si128((__m128i *)(row + 6), out);
            if (op == 3) {
                void (*shuffle)(void *, const void *) = (void *) (code + imm * 32);
                shuffle(row + 6, row + 4);
            }
            if (op == 5) {
                void (*shift)(void *, const void *) = (void *) (code + 8192 + imm * 32);
                shift(row + 6, row + 4);
            }
            if (fwrite(row, sizeof(row), 1, file) != 1) return 1;
        }
    }
    if (munmap(code, 16384) || fclose(file)) return 1;
    return 0;
}
