#define _GNU_SOURCE
#include <asm/ldt.h>
#include <stdint.h>
#include <stdio.h>
#include <sys/syscall.h>
#include <unistd.h>
// Process-local LDT descriptors let native VERR/VERW check data/code permissions
// and presence. The emulator sees equivalent GDT descriptors (it has no LDT).
int main(int argc, char **argv) {
    if (argc != 2) return 2;
    FILE *out = fopen(argv[1], "wb");
    if (!out) return 3;
    unsigned cases = 0;
    for (unsigned content = 0; content < 4; content++)
    for (unsigned ro = 0; ro < 2; ro++)
    for (unsigned absent = 0; absent < 2; absent++) {
        struct user_desc d = {.entry_number=1, .limit=0xffff, .seg_32bit=1,
            .contents=content, .read_exec_only=ro, .seg_not_present=absent,
            .useable=1};
        if (syscall(SYS_modify_ldt, 0x11, &d, sizeof(d)) < 0) continue;
        uint64_t table[2] = {0};
        if (syscall(SYS_modify_ldt, 0, table, sizeof(table)) != sizeof(table)) return 6;
        for (unsigned rpl=0; rpl<4; rpl++) {
            uint16_t sel = 8 | 4 | rpl;
            unsigned char readable, writable;
            __asm__ volatile("verr %1; setz %0" : "=qm"(readable) : "rm"(sel) : "cc");
            __asm__ volatile("verw %1; setz %0" : "=qm"(writable) : "rm"(sel) : "cc");
            uint64_t words[] = {table[1], 16 | rpl, readable, writable};
            if (fwrite(words, sizeof(words), 1, out) != 1) return 4;
            cases++;
        }
    }
    if (fclose(out) || cases < 48) return 5;
    return 0;
}
