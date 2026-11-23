// Successful admission supplies the complete scratch invariant.
requires bytecode_size>=16 && bytecode_size<=268435456;
requires readable_bytes(bytecode,bytecode_size);
requires vm_jit_buffer==0 || writable_bytes(vm_jit_buffer,67108864);
requires vm_jit_buffer==0 || writable_bytes(vm_jit_map,8193*8);
requires vm_jit_buffer==0 || writable_bytes(vm_jit_branches,8192*16);
requires vm_jit_buffer==0 || writable_bytes(vm_jit_errors,524288);
requires vm_jit_buffer==0 || disjoint_bytes(vm_jit_buffer,67108864,vm_jit_map,8193*8);
requires vm_jit_buffer==0 || disjoint_bytes(vm_jit_buffer,67108864,vm_jit_branches,8192*16);
requires vm_jit_buffer==0 || disjoint_bytes(vm_jit_buffer,67108864,vm_jit_errors,524288);
requires vm_jit_buffer==0 || disjoint_bytes(vm_jit_map,8193*8,vm_jit_branches,8192*16);
requires vm_jit_buffer==0 || disjoint_bytes(vm_jit_map,8193*8,vm_jit_errors,524288);
requires vm_jit_buffer==0 || disjoint_bytes(vm_jit_branches,8192*16,vm_jit_errors,524288);
requires vm_jit_buffer==0 || disjoint_bytes(bytecode,bytecode_size,vm_jit_buffer,67108864);
requires vm_jit_buffer==0 || disjoint_bytes(bytecode,bytecode_size,vm_jit_map,8193*8);
requires vm_jit_buffer==0 || disjoint_bytes(bytecode,bytecode_size,vm_jit_branches,8192*16);
requires vm_jit_buffer==0 || disjoint_bytes(bytecode,bytecode_size,vm_jit_errors,524288);
modifies vm_jit_buffer,vm_jit_map,vm_jit_branches,vm_jit_errors;
ensures result==0 || result==1;
ensures readable_bytes(bytecode,bytecode_size);
ensures result==0 || writable_bytes(vm_jit_buffer,67108864);
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
ensures old(vm_jit_buffer)==0 || result==1;
ensures old(vm_jit_buffer)==0 || vm_jit_buffer==old(vm_jit_buffer);
ensures old(vm_jit_buffer)==0 || vm_jit_map==old(vm_jit_map);
ensures old(vm_jit_buffer)==0 || vm_jit_branches==old(vm_jit_branches);
ensures old(vm_jit_buffer)==0 || vm_jit_errors==old(vm_jit_errors);
ensures old(vm_jit_buffer)!=0 || result==0 || fresh_bytes(vm_jit_buffer,67108864);
fn jit_prepare_scratch(bytecode,bytecode_size) {
PRODUCTION_SCRATCH_REUSE_GUARD
PRODUCTION_SCRATCH_INITIAL_ARM
}
