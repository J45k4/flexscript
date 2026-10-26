#include <stdint.h>
typedef int64_t (*callback)(int64_t,int64_t,int64_t,int64_t,int64_t,int64_t);
int64_t invoke(callback f) {
    int64_t a=f(1,2,3,4,5,6);
    int64_t b=f(-1,-2,-3,-4,-5,-6);
    int64_t c=f(10,20,30,40,50,60);
    return a==91 && b==-91 && c==910;
}
