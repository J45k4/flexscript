#include "jit-host.h"
extern long arm64_jit_compile(long, long, long, long, long, long);
static unsigned char generated[1048576];
static long workspace[24576];
static long cached_ir[16384];
static long cached_size, cached_bytes, handle[2];
static long compilations, calls, hits;

void flex_jit_reset(void) {
    flex_jit_release(handle);
    cached_size = cached_bytes = 0;
}
static long same_ir(const long *ir, long bytes) {
    if (!handle[0] || cached_size != bytes) return 0;
    for (long i = 0; i < bytes / 8; i++) if (cached_ir[i] != ir[i]) return 0;
    return 1;
}
long flex_jit_run(const long *ir, long bytes, long *locals, long count,
                  unsigned char *heap, long heap_bytes, long fuel, long deadline_mode, long *out) {
    for (long i = 0; i < 10; i++) out[i] = 0;
    out[3] = fuel;
    if (!ir || bytes < 16 || bytes > 131072 || count < 0 || count > 4096 || ir[1] != count
        || heap_bytes < 0 || heap_bytes > 65536 || (count && !locals) || (heap_bytes && !heap)) {
        out[0] = -2; return -2;
    }
    long cache_hit = same_ir(ir, bytes);
    long size = cached_bytes;
    if (!cache_hit) {
        flex_jit_reset();
        size = arm64_jit_compile((long)ir, bytes, (long)generated, sizeof(generated), (long)workspace, sizeof(workspace));
        if (size <= 0) { out[0] = size; return size; }
        long error = flex_jit_publish(generated, size, handle);
        if (error) { out[0] = error - 1000; return out[0]; }
        for (long i = 0; i < bytes / 8; i++) cached_ir[i] = ir[i];
        cached_size = bytes; cached_bytes = size; compilations++;
    } else { hits++; }
    long now[2] = {0, 0};
    long deadline = 0;
    if (deadline_mode) {
        long error = flex_jit_syscall(113, 1, (long)now, 0, 0, 0, 0);
        if (error) { out[0] = error - 2000; return out[0]; }
        deadline = now[0] * 1000000000L + now[1] + deadline_mode * 1000000L;
    }
    long context[9] = {(long)locals, fuel, 0, 0, deadline, 0, 0, (long)heap, heap_bytes};
    long value = flex_jit_call(handle, context);
    calls++;
    out[0] = size; out[1] = value; out[2] = context[2]; out[3] = context[1];
    out[4] = cache_hit; out[5] = context[3]; out[6] = compilations;
    out[7] = calls; out[8] = handle[0];
    return size;
}
static long heap_hash(const unsigned char *heap, long size) {
    unsigned long hash = 0;
    for (long i = 0; i < size; i++) hash = (hash * 31 + heap[i]) & 0xffffffffUL;
    return (long)hash;
}
long flex_jit_probe(long *stats) {
    const long ir[6] = {18, 0, 1, 42, 9, 0};
    flex_jit_run(ir, sizeof(ir), (void *)0, 0, (void *)0, 0, 100, 0, stats);
    return stats[0] > 0 && !stats[2] ? stats[1] : -10000;
}
long flex_jit_cases(const unsigned char *data, long size, long *results, long capacity) {
    static long locals[4096];
    static unsigned char heap[65536];
    if (!data || !results || size < 8) return -22;
    long count = *(const long *)data;
    if (count < 1 || count > 8192 || capacity < 40 + count * 80) return -22;
    long offset = 8, passed = 0;
    for (long index = 0; index < count; index++) {
        if (offset > size - 80) return -22;
        const long *header = (const long *)(data + offset);
        long bytes = header[0], slots = header[1], heap_bytes = header[2];
        offset += 80;
        if (bytes < 0 || bytes > 131072 || bytes % 8 || slots < 0 || slots > 4096
            || heap_bytes < 0 || heap_bytes > 65536 || heap_bytes % 8
            || slots * 8 + heap_bytes + bytes > size - offset) return -22;
        const long *initial = (const long *)(data + offset);
        for (long i = 0; i < slots; i++) locals[i] = initial[i];
        offset += slots * 8;
        for (long i = 0; i < heap_bytes; i++) heap[i] = data[offset + i];
        offset += heap_bytes;
        long *record = results + 5 + index * 10;
        flex_jit_run((const long *)(data + offset), bytes, locals, slots, heap, heap_bytes, header[3], header[4], record);
        offset += bytes;
        record[9] = heap_hash(heap, heap_bytes);
        long compiled = header[5] == 1 ? record[0] > 0 : record[0] == header[5];
        if (compiled && record[1] == header[6] && record[2] == header[7]
            && (header[8] == -1 || record[3] == header[8]) && record[9] == header[9]) passed++;
    }
    if (offset != size) return -22;
    results[0] = count; results[1] = passed; results[2] = compilations; results[3] = calls; results[4] = hits;
    return (passed << 32) | count;
}
