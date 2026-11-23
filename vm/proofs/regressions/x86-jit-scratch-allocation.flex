fn main() {
    if !jit_allocate_scratch_view() {return 1;}
    store8(vm_jit_buffer,11);store8(vm_jit_buffer+67108863,12);
    store8(vm_jit_map,21);store8(vm_jit_map+8193*8-1,22);
    store8(vm_jit_branches,31);store8(vm_jit_branches+8192*16-1,32);
    store8(vm_jit_errors,41);store8(vm_jit_errors+8192*64-1,42);
    if load8(vm_jit_buffer)!=11 || load8(vm_jit_buffer+67108863)!=12 ||
        load8(vm_jit_map)!=21 || load8(vm_jit_map+8193*8-1)!=22 ||
        load8(vm_jit_branches)!=31 || load8(vm_jit_branches+8192*16-1)!=32 ||
        load8(vm_jit_errors)!=41 || load8(vm_jit_errors+8192*64-1)!=42 {return 2;}
    if syscall(11,vm_jit_buffer,67108864,0,0,0,0)<0 ||
        syscall(11,vm_jit_map,8193*8,0,0,0,0)<0 ||
        syscall(11,vm_jit_branches,8192*16,0,0,0,0)<0 ||
        syscall(11,vm_jit_errors,8192*64,0,0,0,0)<0 {return 3;}
    return 0;
}
