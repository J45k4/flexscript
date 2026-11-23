// Fresh scratch allocation keeps the already-live bytecode extent separate.
requires vm_jit_buffer==0;
requires bytecode_size>=16 && bytecode_size<=268435456;
requires readable_bytes(bytecode,bytecode_size);
modifies vm_jit_buffer,vm_jit_map,vm_jit_branches,vm_jit_errors;
ensures result==0 || result==1;
ensures readable_bytes(bytecode,bytecode_size);
ensures result==0 || disjoint_bytes(bytecode,bytecode_size,vm_jit_buffer,67108864);
ensures result==0 || disjoint_bytes(bytecode,bytecode_size,vm_jit_map,8193*8);
ensures result==0 || disjoint_bytes(bytecode,bytecode_size,vm_jit_branches,8192*16);
ensures result==0 || disjoint_bytes(bytecode,bytecode_size,vm_jit_errors,524288);
PRODUCTION_SCRATCH_BYTECODE_ALLOCATIONS
