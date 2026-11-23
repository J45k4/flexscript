// The final cache decision keeps the scratch ownership needed by the next compile.
global output=0;
global output_size=0;
global vm_mode=0;
global vm_jit_cache=0;
global vm_jit_bytes=0;
global vm_jit_compilations=0;
global vm_jit_buffer=0;
global vm_jit_map=0;
global vm_jit_branches=0;
global vm_jit_errors=0;

requires bytecode_size>=16 && bytecode_size<=268435456;
requires index>=0 && index<18432;
requires code==0 || code>0 && bytes>=4096 && bytes<=1048576 && !(bytes%4096);
requires vm_jit_bytes>=0 && vm_jit_bytes<=16777216;
requires code==0 || bytes<=16777216-vm_jit_bytes;
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
requires readable_bytes(bytecode,bytecode_size);
requires writable_bytes(vm_jit_cache+index*32,16);
requires disjoint_bytes(bytecode,bytecode_size,vm_jit_cache+index*32,16);
modifies output,output_size,vm_mode,vm_jit_bytes,vm_jit_compilations,bytes(vm_jit_cache+index*32,16);
ensures output==bytecode && output_size==bytecode_size && vm_mode==1;
ensures result==code;
ensures writable_bytes(vm_jit_buffer,67108864);
ensures writable_bytes(vm_jit_map,8193*8);
ensures writable_bytes(vm_jit_branches,8192*16);
ensures writable_bytes(vm_jit_errors,524288);
ensures disjoint_bytes(vm_jit_buffer,67108864,vm_jit_map,8193*8);
ensures disjoint_bytes(vm_jit_buffer,67108864,vm_jit_branches,8192*16);
ensures disjoint_bytes(vm_jit_buffer,67108864,vm_jit_errors,524288);
ensures disjoint_bytes(vm_jit_map,8193*8,vm_jit_branches,8192*16);
ensures disjoint_bytes(vm_jit_map,8193*8,vm_jit_errors,524288);
ensures disjoint_bytes(vm_jit_branches,8192*16,vm_jit_errors,524288);
ensures disjoint_bytes(bytecode,bytecode_size,vm_jit_buffer,67108864);
ensures disjoint_bytes(bytecode,bytecode_size,vm_jit_map,8193*8);
ensures disjoint_bytes(bytecode,bytecode_size,vm_jit_branches,8192*16);
ensures disjoint_bytes(bytecode,bytecode_size,vm_jit_errors,524288);
ensures readable_bytes(bytecode,bytecode_size);
fn jit_restore_scratch_after_publication(index,bytecode,bytecode_size,code,bytes) {
PRODUCTION_CACHE_RETIREMENT
}
