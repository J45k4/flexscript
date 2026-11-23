// The gate inserts the four allocations and admission guard from vm_jit_compile.
// The syscall-backed allocator is modeled by the verifier allocation primitive.
global vm_jit_buffer=0;
global vm_jit_map=0;
global vm_jit_branches=0;
global vm_jit_errors=0;

requires vm_jit_buffer==0;
modifies vm_jit_buffer,vm_jit_map,vm_jit_branches,vm_jit_errors;
ensures result==0 || result==1;
ensures result==0 || writable_bytes(vm_jit_buffer,67108864);
ensures result==0 || writable_bytes(vm_jit_map,8193*8);
ensures result==0 || writable_bytes(vm_jit_branches,8192*16);
ensures result==0 || writable_bytes(vm_jit_errors,8192*64);
ensures result==0 || fresh_bytes(vm_jit_buffer,67108864);
ensures result==0 || fresh_bytes(vm_jit_map,8193*8);
ensures result==0 || fresh_bytes(vm_jit_branches,8192*16);
ensures result==0 || fresh_bytes(vm_jit_errors,8192*64);
ensures result==0 || disjoint_bytes(vm_jit_buffer,67108864,vm_jit_map,8193*8);
ensures result==0 || disjoint_bytes(vm_jit_buffer,67108864,vm_jit_branches,8192*16);
ensures result==0 || disjoint_bytes(vm_jit_buffer,67108864,vm_jit_errors,8192*64);
ensures result==0 || disjoint_bytes(vm_jit_map,8193*8,vm_jit_branches,8192*16);
ensures result==0 || disjoint_bytes(vm_jit_map,8193*8,vm_jit_errors,8192*64);
ensures result==0 || disjoint_bytes(vm_jit_branches,8192*16,vm_jit_errors,8192*64);
fn jit_allocate_scratch_view() {
PRODUCTION_STAGING_ALLOCATION
    proof {
        if vm_jit_buffer>0 {assert writable_bytes(vm_jit_buffer,67108864);}
    }
PRODUCTION_MAP_ALLOCATION
    proof {
        if vm_jit_buffer>0 {assert writable_bytes(vm_jit_buffer,67108864);}
        if vm_jit_map>0 {assert writable_bytes(vm_jit_map,8193*8);}
    }
PRODUCTION_BRANCH_ALLOCATION
    proof {
        if vm_jit_buffer>0 {assert writable_bytes(vm_jit_buffer,67108864);}
        if vm_jit_map>0 {assert writable_bytes(vm_jit_map,8193*8);}
        if vm_jit_branches>0 {assert writable_bytes(vm_jit_branches,8192*16);}
    }
PRODUCTION_ERROR_ALLOCATION
PRODUCTION_SCRATCH_GUARD
    return 1;
}
