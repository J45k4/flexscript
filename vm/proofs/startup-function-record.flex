// Appended to the checked core startup and compiler metadata profiles.
requires vm_fd_observed>=0 && vm_fd_observed<67;
requires vm_heap_limit>=4096 && vm_heap_limit<=1000000000;
requires function_capacity>=0 && function_capacity<=16384;
requires writable_bytes(address,8);
modifies vm_heap,vm_stack,vm_local_memory,vm_frames,vm_time,vm_path,vm_open_how,vm_fds,vm_jit_cache,vm_jit_context,vm_poll_records,vm_file_stat;
ensures load64(address)==old(load64(address));
ensures writable_bytes(address,8);
fn startup_preserves_existing_word(address,function_capacity) {
    return vm_initialize_buffers(function_capacity);
}

// Follow the ordering used by vm_main. The parser and bytecode generation
// lie between these stages in the runtime and still need their own proofs.
requires vm_fd_observed>=0 && vm_fd_observed<67;
requires vm_heap_limit>=4096 && vm_heap_limit<=1000000000;
requires function_capacity>=0 && function_capacity<=16384;
requires code_capacity>=16 && code_capacity<=268435456;
requires function_count>=0 && function_count<function_capacity+2048;
requires output_size>=0 && output_size<=code_capacity;
requires arity>=0 && arity<=4096;
modifies output,globals,functions,function_count,vm_heap,vm_stack,vm_local_memory,vm_frames,vm_time,vm_path,vm_open_how,vm_fds,vm_jit_cache,vm_jit_context,vm_poll_records,vm_file_stat;
ensures result>=-1;
ensures result<0 || (observe_arity || result==output_size);
ensures result<0 || (!observe_arity || result==arity);
ensures result<0 || writable_bytes(vm_heap,vm_heap_limit);
ensures result<0 || disjoint_bytes(vm_heap,vm_heap_limit,output,code_capacity);
ensures result<0 || disjoint_bytes(vm_heap,vm_heap_limit,functions,(function_capacity+2048)*32);
ensures result<0 || disjoint_bytes(output,code_capacity,functions,(function_capacity+2048)*32);
ensures vm_depth==old(vm_depth) && vm_sp==old(vm_sp);
fn startup_allocate_read_record(name,size,arity,code_capacity,function_capacity,observe_arity) {
    if !vm_initialize_buffers(function_capacity) {return -1;}
    return allocate_then_read_installed_record(name,size,arity,code_capacity,function_capacity,observe_arity);
}
