import "../lib/ffi.flex";
fn main() {
    let libc=ffi_open("libc.so.6");if !libc {return 1;}
    let strlen=ffi_symbol(libc,"strlen");if !strlen {return 2;}
    let n=ffi_call(strlen,"Hello through C FFI!\n",0,0,0,0,0);
    syscall(1,1,"Hello through C FFI!\n",n,0,0,0);ffi_close(libc);return 0;
}
