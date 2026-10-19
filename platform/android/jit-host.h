#ifndef FLEX_ANDROID_JIT_HOST_H
#define FLEX_ANDROID_JIT_HOST_H
long flex_jit_syscall(long, long, long, long, long, long, long);
long flex_jit_publish(const unsigned char *, long, long *);
long flex_jit_call(const long *, long *);
long flex_jit_release(long *);
long flex_jit_run(const long *, long, long *, long, unsigned char *, long, long, long, long *);
long flex_jit_cases(const unsigned char *, long, long *, long);
long flex_jit_probe(long *);
void flex_jit_reset(void);
#endif
