// Linux x86-64 System V call bridge for eleven integer/pointer arguments.
// Arguments seven through eleven occupy the aligned outgoing stack frame.
global ffi_words_stub=0;
fn ffi_call_words(function,words) {
    if !ffi_words_stub {
        let p=alloc(4096);if p<0 {return -10003;}
        store64(p+0,0x8348f38949f88948);
        store64(p+8,0x894c30538b4d28ec);
        store64(p+16,0x894c38538b4d2414);
        store64(p+24,0x4c40538b4d082454);
        store64(p+32,0x48538b4d10245489);
        store64(p+40,0x538b4d182454894c);
        store64(p+48,0x8b49202454894c50);
        store64(p+56,0x538b4908738b493b);
        store64(p+64,0x438b4d184b8b4910);
        store64(p+72,0x48d0ff284b8b4d20);
        store8(p+80,131);
        store8(p+81,196);
        store8(p+82,40);
        store8(p+83,195);
        if syscall(10,p,4096,5,0,0,0)<0 {syscall(11,p,4096,0,0,0,0);return -10003;}
        ffi_words_stub=p;
    }
    return ffi_call(ffi_words_stub,function,words,0,0,0,0);
}
