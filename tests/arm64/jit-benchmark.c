#include "../../platform/android/jit-host.h"
extern long arm64_jit_compile(long, long, long, long, long, long);
typedef unsigned long Word;
static unsigned char code[1048576];
static unsigned char emitted[2][4096];
static long scratch[24576], ir[256], words, handle[2];
static Word heap[258], locals[3];
static volatile Word sink;
static long deadline;
#ifndef BENCH_DEADLINE
#define BENCH_DEADLINE 0
#endif
static long now(void) {
    long ts[2];
    if (flex_jit_syscall(113, 1, (long)ts, 0, 0, 0, 0)) return -1;
    return ts[0] * 1000000000L + ts[1];
}
static void emit(long op, long arg) { ir[words++] = op; ir[words++] = arg; }
static void kernel(long array) {
    words = 0; emit(18, 3);
    long top = words * 8;
    emit(3, 1); emit(2, 0); emit(3, 0); emit(7, 60);
    long exit = words + 1; emit(11, 0);
    if (array) {
        emit(3, 1); emit(2, 0); emit(1, 255); emit(7, 38);
        emit(2, 0); emit(21, (256L << 32) | 16);
        emit(2, 0); emit(3, 1); emit(7, 43);
        emit(22, (256L << 32) | 16);
    }
    emit(3, 2); emit(2, 0); emit(3, 1); emit(7, 43);
    emit(2, 0); emit(1, 33); emit(7, 42);
    emit(2, 0); emit(3, 1); emit(7, 94); emit(4, 2);
    emit(3, 1); emit(2, 0); emit(1, 1); emit(7, 43); emit(4, 1);
    emit(10, top); ir[exit] = words * 8; emit(3, 2); emit(9, 0);
}
static void reset(void) {
    locals[0] = 20000; locals[1] = 0; locals[2] = 7;
    for (long i = 0; i < 258; i++) heap[i] = i;
}
__attribute__((noinline)) static Word native_hash(void) {
    Word hash = locals[2];
    for (Word i = 0; i < locals[0]; i++) hash = (hash + i) * 33 ^ i;
    return hash;
}
__attribute__((noinline)) static Word native_array(void) {
    Word hash = locals[2];
    for (Word i = 0; i < locals[0]; i++) {
        heap[2 + (i & 255)] += i;
        hash = (hash + i) * 33 ^ i;
    }
    return hash;
}
static Word native(long array) { return array ? native_array() : native_hash(); }
static Word interpreter(long *ctx) {
    Word l[3] = {locals[0], locals[1], locals[2]}, stack[8], a = 0;
    long pc = 2, depth = 0;
    for (;;) {
        if (ctx[1] <= 0) { ctx[2] = 1; return 0; }
        ctx[1]--;
        long op = ir[pc], arg = ir[pc + 1];
        if (op == 1) a = arg;
        else if (op == 2) stack[depth++] = a;
        else if (op == 3) a = l[arg];
        else if (op == 4) l[arg] = a;
        else if (op == 7) {
            Word left = stack[--depth];
            if (arg == 43) a = left + a;
            else if (arg == 42) a = left * a;
            else if (arg == 94) a = left ^ a;
            else if (arg == 38) a = left & a;
            else a = (long)left < (long)a;
        } else if (op == 21 || op == 22) {
            Word index = op == 21 ? a : stack[--depth];
            Word base = (Word)arg & 0xffffffffUL, span = (Word)arg >> 32;
            if (index >= span || base + span * 8 > (Word)ctx[8] || !ctx[7]) {
                ctx[2] = 3; return 0;
            }
            Word *address = (Word *)(ctx[7] + base + index * 8);
            if (op == 21) a = *address; else *address = a;
        } else if (op == 10 || op == 11) {
            if (arg <= pc * 8) ctx[3]++;
            if (op == 10 || !a) { pc = arg / 8; continue; }
        } else if (op == 9) return a;
        else { ctx[2] = -1; return 0; }
        pc += 2;
    }
}
static Word hash_heap(void) {
    Word h = 0; for (long i = 0; i < 258; i++) h = h * 31 + heap[i]; return h;
}
// Binary records: kernel, code bytes, compile ns, then nine samples of
// native-C/interpreter/JIT nanoseconds. Each sample contains 32 warm calls.
long runner_main(void) {
    long records[2][30];
    if (BENCH_DEADLINE) deadline = now() + 180000000000L;
    for (long array = 0; array < 2; array++) {
        kernel(array);
        long start = now();
        long size = arm64_jit_compile((long)ir, words * 8, (long)code, sizeof(code), (long)scratch, sizeof(scratch));
        records[array][0] = array; records[array][1] = size; records[array][2] = now() - start;
        if (size <= 0 || size > (long)sizeof(emitted[array])) return 6;
        for (long i = 0; i < size; i++) emitted[array][i] = code[i];
        if (size <= 0 || flex_jit_publish(code, size, handle)) return 1;
        Word expected = 0, expected_heap = 0; long fuel = 0, backedges = 0;
        for (long engine = 0; engine < 3; engine++) {
            reset(); long ctx[9] = {(long)locals, 10000000, 0, 0, deadline, 0, 0, (long)heap, sizeof(heap)};
            Word value = engine == 0 ? native(array) : engine == 1 ? interpreter(ctx) : (Word)flex_jit_call(handle, ctx);
            if (!engine) { expected = value; expected_heap = hash_heap(); }
            else if (value != expected || hash_heap() != expected_heap || ctx[2]) return 2;
            if (engine == 1) { fuel = ctx[1]; backedges = ctx[3]; }
            if (engine == 2 && (fuel != ctx[1] || backedges != ctx[3])) return 3;
        }
        for (long sample = 0; sample < 9; sample++) {
            // Rotate order to reduce systematic warmup and scheduling bias.
            for (long step = 0; step < 3; step++) {
                long engine = (step + sample) % 3, elapsed = 0;
                for (long repeat = 0; repeat < 32; repeat++) {
                    reset(); long ctx[9] = {(long)locals, 10000000, 0, 0, deadline, 0, 0, (long)heap, sizeof(heap)};
                    start = now();
                    Word value = engine == 0 ? native(array) : engine == 1 ? interpreter(ctx) : (Word)flex_jit_call(handle, ctx);
                    elapsed += now() - start; sink = value;
                    if (value != expected || ctx[2]) return 4;
                }
                records[array][3 + sample * 3 + engine] = elapsed;
            }
        }
        flex_jit_release(handle);
    }
    if (flex_jit_syscall(64, 1, (long)records, sizeof(records), 0, 0, 0) != sizeof(records)) return 5;
    for (long i = 0; i < 2; i++) {
        long size = records[i][1];
        if (flex_jit_syscall(64, 1, (long)emitted[i], size, 0, 0, 0) != size) return 7;
    }
    return 0;
}
