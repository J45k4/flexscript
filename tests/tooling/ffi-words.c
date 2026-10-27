// Independent test oracle only, never an application FFI shim.
#include <stdint.h>
#include <stdarg.h>
int64_t words12(int64_t a,int64_t b,int64_t c,int64_t d,int64_t e,int64_t f,
                int64_t g,int64_t h,int64_t i,int64_t j,int64_t k,int64_t l) {
    return a+2*b+3*c+4*d+5*e+6*f+7*g+8*h+9*i+10*j+11*k+12*l;
}
int64_t words_varargs(int count,...) {
    va_list args;va_start(args,count);int64_t sum=0;
    for(int i=0;i<count;i++)sum+=va_arg(args,int64_t)*(i+1);
    va_end(args);return sum;
}
