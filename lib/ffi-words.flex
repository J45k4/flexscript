// Owned Linux x86-64 SysV adapter for 0..12 integer/pointer arguments.
// No floating-point by-value arguments. Arrays of floats may be passed by pointer.
// Code is written RW, then sealed RX. Contexts are private to one calling thread.
import "native.flex";
// Preserve the established eleven-word helper used by GPU/render consumers.
// Like its original implementation this compatibility context is thread-local
// by convention. New code should use explicit owned contexts above/below.
global ffi_words_compat_context=0;
fn ffi_call_words(function,words){
    if !ffi_words_compat_context{ffi_words_compat_context=ffi_words_context();}
    if !ffi_words_compat_context{return -10003;}
    return ffi_words_call(ffi_words_compat_context,function,words,11);
}
fn ffi_call_words_close(){ffi_words_free(ffi_words_compat_context);ffi_words_compat_context=0;return 0;}
fn ffi_words_context(){
    let c=alloc(128);let code=alloc(4096);if c<0 || code<0{if c>0{syscall(11,c,128,0,0,0,0);}if code>0{syscall(11,code,4096,0,0,0,0);}return 0;}
    // Descriptor: function, six register arguments, then six stack arguments.
    // RSP is 16-byte aligned at the foreign call. AL=0 for integer varargs.
    let hex="4989fa4883ec38498b423848890424498b42404889442408498b42484889442410498b42504889442418498b42584889442420498b42604889442428498b7a08498b7210498b5218498b4a204d8b42284d8b4a304d8b1a31c041ffd34883c438c3";
    let at=0;while load8(hex+at*2){let a=load8(hex+at*2);let b=load8(hex+at*2+1);if a>57{a=a-87;}else{a=a-48;}if b>57{b=b-87;}else{b=b-48;}store8(code+at,(a<<4)|b);at=at+1;}
    if syscall(10,code,4096,5,0,0,0)<0{syscall(11,c,128,0,0,0,0);syscall(11,code,4096,0,0,0,0);return 0;}store64(c,code);return c;
}
fn ffi_words_call(c,function,args,count){
    if !c || !function || count<0 || count>12 || (count && !args){return 0;}
    store64(c+16,function);let i=0;while i<12{let value=0;if i<count{value=load64(args+i*8);}store64(c+24+i*8,value);i=i+1;}
    return native_call1(load64(c),c+16);
}
fn ffi_words_free(c){if c{syscall(11,load64(c),4096,0,0,0,0);syscall(11,c,128,0,0,0,0);}return 0;}
