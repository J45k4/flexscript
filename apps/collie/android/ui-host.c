/* Pure Flexscript UI host: independent globals/arena/JNI lock from agent execution. */
extern long uh_entry(long, long, long, long);
static long raw(long n, long a, long b, long c, long d, long e, long f) {
    register long x8 __asm__("x8")=n,x0 __asm__("x0")=a,x1 __asm__("x1")=b,
        x2 __asm__("x2")=c,x3 __asm__("x3")=d,x4 __asm__("x4")=e,x5 __asm__("x5")=f;
    __asm__ volatile("svc #0":"+r"(x0):"r"(x8),"r"(x1),"r"(x2),"r"(x3),"r"(x4),"r"(x5):"memory");return x0;
}
static long length(const char *s){long n=0;while(s[n])n++;return n;}
static void copy(char *out,const char *in,long n){while(n-->0)*out++=*in++;}
static long checkpoint[13], heap, used;
static char diagnostic[512];
static long diagnostic_n;
static const char *problem;
__attribute__((returns_twice)) long uh_checkpoint(long *);
__attribute__((noreturn)) void uh_abort(long *);
__asm__(".text\n.hidden uh_checkpoint\n.type uh_checkpoint,%function\nuh_checkpoint:\n"
        "stp x19,x20,[x0]\nstp x21,x22,[x0,#16]\nstp x23,x24,[x0,#32]\nstp x25,x26,[x0,#48]\nstp "
        "x27,x28,[x0,#64]\nstp x29,x30,[x0,#80]\nmov x1,sp\nstr x1,[x0,#96]\nmov x0,#0\nret\n"
        ".hidden uh_abort\n.type uh_abort,%function\nuh_abort:\n"
        "ldp x19,x20,[x0]\nldp x21,x22,[x0,#16]\nldp x23,x24,[x0,#32]\nldp x25,x26,[x0,#48]\nldp "
        "x27,x28,[x0,#64]\nldp x29,x30,[x0,#80]\nldr x1,[x0,#96]\nmov sp,x1\nmov x0,#1\nret\n");
#define UI_HEAP 134217728
static void fail(const char *message){problem=message;uh_abort(checkpoint);}
static long allocate(long size){
    if(size<0 || size>UI_HEAP-used-8)fail("UI arena limit exceeded.");
    long p=heap+used;used+=(size+7)&~7L;return p;
}
static long callback(long number,long *args){
    if(number==1000)return allocate(args[0]);
    if(number==1 && args[0]==2){
        long n=args[2];if(n<0)return -22;
        long count=n;if(count>511-diagnostic_n)count=511-diagnostic_n;
        copy(diagnostic+diagnostic_n,(const char *)args[1],count);diagnostic_n+=count;diagnostic[diagnostic_n]=0;return n;
    }
    if(number==60 || number==231)fail(diagnostic_n?diagnostic:"UI program rejected its input.");
    return -38; /* UI evaluation has no filesystem, network, process or device calls. */
}
long collie_ui_call(long op,const char *input,long size,char *out,long capacity,const char *unused){
    (void)unused;
    if(!input || !out || size<0 || size>8388608 || capacity<4096)return -22;
    heap=raw(222,0,UI_HEAP,3,34,-1,0);if(heap<0)return heap;
    used=16;diagnostic_n=0;problem="UI evaluation failed.";
    long result=0;
    if(!uh_checkpoint(checkpoint)){
        long text=allocate(size+1);copy((char *)text,input,size);
        long packet[6];long value=uh_entry(op,text,(long)callback,(long)packet);long n=length((const char *)value);
        if(n>=capacity)fail("UI reply limit exceeded.");copy(out,(const char *)value,n);result=n;
    }else{
        const char *head="{\"error\":\"";long n=length(head);copy(out,head,n);
        for(const char *p=problem;*p && n<capacity-10;p++){
            unsigned char c=(unsigned char)*p;
            if(c=='"' || c=='\\')out[n++]='\\';
            if(c<32)out[n++]=' ';else out[n++]=(char)c;
        }
        out[n++]='"';out[n++]='}';result=n;
    }
    raw(215,heap,UI_HEAP,0,0,0,0);heap=0;return result;
}
static void *address(void *env,void *buffer){
    if(!buffer)return (void *)0;const void *const *t=*(const void *const **)env;
    return ((void *(*)(void *,void *))t[230])(env,buffer);
}
static long capacity(void *env,void *buffer){
    if(!buffer)return -1;const void *const *t=*(const void *const **)env;
    return ((long (*)(void *,void *))t[231])(env,buffer);
}
__attribute__((visibility("default"))) long
Java_org_flexscript_collie_MainActivity_nativeUiCall(void *env,void *clazz,void *input,long size,void *output){
    (void)clazz;if(size>capacity(env,input))return -22;
    return collie_ui_call(11,address(env,input),size,address(env,output),capacity(env,output),"");
}
