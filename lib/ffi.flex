// Integer and pointer FFI for the Linux x86-64 System V ABI.
// ffi_open(name), ffi_symbol(handle,name), and ffi_call[_i32|_u32]
// (pointer,a,b,c,d,e,f) are provided by the compiler. Unused arguments are zero.
global ffi_close_library=0;
global ffi_close_symbol=0;
fn ffi_close(handle) {
    if !handle {return -1;}
    if !ffi_close_symbol {
        ffi_close_library=ffi_open("libc.so.6");if !ffi_close_library {return -1;}
        ffi_close_symbol=ffi_symbol(ffi_close_library,"dlclose");if !ffi_close_symbol {return -1;}
    }
    return ffi_call_i32(ffi_close_symbol,handle,0,0,0,0,0);
}
