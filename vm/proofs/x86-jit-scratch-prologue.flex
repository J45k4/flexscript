// The successful prologue carries scratch ownership from initial allocation
// or reuse to the entry of the production body emission loop.
requires vm_jit_buffer==0;
requires bytecode_size>=16 && bytecode_size<=268435456;
requires readable_bytes(bytecode,bytecode_size);
requires slots>=0 && slots<=4096;
modifies vm_jit_buffer,vm_jit_map,vm_jit_branches,vm_jit_errors,output,output_size,vm_mode,output_limit,vm_jit_context_slot,vm_jit_branch_count,vm_jit_error_count,native_boolean_end,native_address_site;
ensures result==0 || result==1;
ensures readable_bytes(bytecode,bytecode_size);
ensures result==0 || writable_bytes(output,67108864);
ensures result==0 || writable_bytes(vm_jit_map,8193*8);
ensures result==0 || writable_bytes(vm_jit_branches,8192*16);
ensures result==0 || writable_bytes(vm_jit_errors,524288);
ensures result==0 || disjoint_bytes(vm_jit_buffer,67108864,vm_jit_map,8193*8);
ensures result==0 || disjoint_bytes(vm_jit_buffer,67108864,vm_jit_branches,8192*16);
ensures result==0 || disjoint_bytes(vm_jit_buffer,67108864,vm_jit_errors,524288);
ensures result==0 || disjoint_bytes(vm_jit_map,8193*8,vm_jit_branches,8192*16);
ensures result==0 || disjoint_bytes(vm_jit_map,8193*8,vm_jit_errors,524288);
ensures result==0 || disjoint_bytes(vm_jit_branches,8192*16,vm_jit_errors,524288);
ensures result==0 || disjoint_bytes(bytecode,bytecode_size,vm_jit_buffer,67108864);
ensures result==0 || disjoint_bytes(bytecode,bytecode_size,vm_jit_map,8193*8);
ensures result==0 || disjoint_bytes(bytecode,bytecode_size,vm_jit_branches,8192*16);
ensures result==0 || disjoint_bytes(bytecode,bytecode_size,vm_jit_errors,524288);
ensures result==0 || (output==vm_jit_buffer && output_limit==67108864 && vm_mode==0);
ensures result==0 || (output_size>=21 && output_size<=57365);
ensures result==0 || (vm_jit_branch_count==0 && vm_jit_error_count==0);
fn jit_enter_body_with_fresh_scratch(bytecode,bytecode_size,slots) {
    if !jit_prepare_scratch(bytecode,bytecode_size) {return 0;}
    jit_begin_and_emit_prologue(slots);
    return 1;
}

requires vm_jit_buffer!=0;
requires bytecode_size>=16 && bytecode_size<=268435456;
requires readable_bytes(bytecode,bytecode_size);
requires writable_bytes(vm_jit_buffer,67108864);
requires writable_bytes(vm_jit_map,8193*8);
requires writable_bytes(vm_jit_branches,8192*16);
requires writable_bytes(vm_jit_errors,524288);
requires disjoint_bytes(vm_jit_buffer,67108864,vm_jit_map,8193*8);
requires disjoint_bytes(vm_jit_buffer,67108864,vm_jit_branches,8192*16);
requires disjoint_bytes(vm_jit_buffer,67108864,vm_jit_errors,524288);
requires disjoint_bytes(vm_jit_map,8193*8,vm_jit_branches,8192*16);
requires disjoint_bytes(vm_jit_map,8193*8,vm_jit_errors,524288);
requires disjoint_bytes(vm_jit_branches,8192*16,vm_jit_errors,524288);
requires disjoint_bytes(bytecode,bytecode_size,vm_jit_buffer,67108864);
requires disjoint_bytes(bytecode,bytecode_size,vm_jit_map,8193*8);
requires disjoint_bytes(bytecode,bytecode_size,vm_jit_branches,8192*16);
requires disjoint_bytes(bytecode,bytecode_size,vm_jit_errors,524288);
requires slots>=0 && slots<=4096;
modifies output,output_size,vm_mode,output_limit,vm_jit_context_slot,vm_jit_branch_count,vm_jit_error_count,native_boolean_end,native_address_site,bytes(vm_jit_buffer,67108864);
ensures result==0 || result==1;
ensures readable_bytes(bytecode,bytecode_size);
ensures result==0 || writable_bytes(output,67108864);
ensures result==0 || writable_bytes(vm_jit_map,8193*8);
ensures result==0 || writable_bytes(vm_jit_branches,8192*16);
ensures result==0 || writable_bytes(vm_jit_errors,524288);
ensures result==0 || disjoint_bytes(vm_jit_buffer,67108864,vm_jit_map,8193*8);
ensures result==0 || disjoint_bytes(vm_jit_buffer,67108864,vm_jit_branches,8192*16);
ensures result==0 || disjoint_bytes(vm_jit_buffer,67108864,vm_jit_errors,524288);
ensures result==0 || disjoint_bytes(vm_jit_map,8193*8,vm_jit_branches,8192*16);
ensures result==0 || disjoint_bytes(vm_jit_map,8193*8,vm_jit_errors,524288);
ensures result==0 || disjoint_bytes(vm_jit_branches,8192*16,vm_jit_errors,524288);
ensures result==0 || disjoint_bytes(bytecode,bytecode_size,vm_jit_buffer,67108864);
ensures result==0 || disjoint_bytes(bytecode,bytecode_size,vm_jit_map,8193*8);
ensures result==0 || disjoint_bytes(bytecode,bytecode_size,vm_jit_branches,8192*16);
ensures result==0 || disjoint_bytes(bytecode,bytecode_size,vm_jit_errors,524288);
ensures result==0 || (output==vm_jit_buffer && output_limit==67108864 && vm_mode==0);
ensures result==0 || (output_size>=21 && output_size<=57365);
ensures result==0 || (vm_jit_branch_count==0 && vm_jit_error_count==0);
fn jit_enter_body_with_reused_scratch(bytecode,bytecode_size,slots) {
PRODUCTION_REUSE_GUARD
    jit_begin_and_emit_prologue(slots);
    return 1;
}
