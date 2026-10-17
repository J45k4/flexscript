/* Minimal freestanding JNI bridge; no libc or NDK runtime dependency.
 * JNI specifies fixed function-table slots 230/231 for direct buffers:
 * https://docs.oracle.com/en/java/javase/17/docs/specs/jni/functions.html
 * Only this host boundary is C; rendering and computation are Flexscript.
 */
_Static_assert(sizeof(long) == 8 && sizeof(void *) == 8, "64-bit Android ABI required");
#include "../../platform/android/jit-host.h"
extern long flexscript_main(long count, long words);

static void *direct_address(void *env, void *buffer) {
    if (!buffer) return (void *)0;
    const void *const *table = *(const void *const **)env;
    void *(*address)(void *, void *) = (void *(*)(void *, void *))table[230];
    return address(env, buffer);
}
static long direct_capacity(void *env, void *buffer) {
    if (!buffer) return -1;
    const void *const *table = *(const void *const **)env;
    long (*capacity)(void *, void *) = (long (*)(void *, void *))table[231];
    return capacity(env, buffer);
}

__attribute__((visibility("default")))
long Java_org_flexscript_demo_MainActivity_jitProbe(void *env, void *clazz, void *stats) {
    (void)clazz;
    long *out = direct_address(env, stats);
    if (!out || direct_capacity(env, stats) < 80) return -22;
    return flex_jit_probe(out);
}
__attribute__((visibility("default")))
long Java_org_flexscript_demo_MainActivity_runJitCases(void *env, void *clazz, void *requests, void *results) {
    (void)clazz;
    const unsigned char *data = direct_address(env, requests);
    long *out = direct_address(env, results);
    return flex_jit_cases(data, direct_capacity(env, requests), out, direct_capacity(env, results));
}

__attribute__((visibility("default")))
long Java_org_flexscript_demo_MainActivity_render(
    void *env, void *clazz, void *buffer, int width, int height, long touches) {
    (void)clazz;
    if (!buffer || width <= 0 || width > 1024 || height <= 0 || height > 1024) return -20;
    void *pixels = direct_address(env, buffer);
    long size = direct_capacity(env, buffer);
    if (!pixels || size < (long)width * height * 4) return -21;
    long words[5] = {(long)pixels, width, height, touches, size};
    return flexscript_main(5, (long)words);
}
