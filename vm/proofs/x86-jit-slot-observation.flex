// A word disjoint from the slot's four write regions survives the full
// production map store, meter, operand loads, and opcode dispatch.
requires base>=21 && base<=57365;
requires slot>=1 && slot<8192;
requires output_size>=base && output_size<=base+256*(slot-1);
requires vm_jit_error_count>=0 && vm_jit_error_count<=3*(slot-1);
requires vm_jit_branch_count>=0 && vm_jit_branch_count<=slot-1;
requires output_limit==67108864;
requires vm_mode==0 && native_branch_mode==0;
requires !native_register_frame || !native_reg_replay;
requires vm_restricted!=0;
requires vm_heap_used>=16 && vm_heap_used<=1000000000;
requires vm_heap>0 && vm_heap<=0x7fffffffffffffff-vm_heap_used;
requires pc>=start+16 && pc<end && end<=268435456;
requires start>=0 && slots>=0 && slots<=4096;
requires bytecode_size>=16 && bytecode_size<=268435456;
requires pc>=0 && pc<=bytecode_size-16;
requires readable_bytes(bytecode,bytecode_size);
requires writable_bytes(output,67108864);
requires writable_bytes(vm_jit_errors,524288);
requires writable_bytes(vm_jit_branches,8192*16);
requires disjoint_bytes(output,67108864,vm_jit_errors,524288);
requires disjoint_bytes(output,67108864,vm_jit_branches,8192*16);
requires disjoint_bytes(vm_jit_errors,524288,vm_jit_branches,8192*16);
requires writable_bytes(vm_jit_map,8193*8);
requires disjoint_bytes(output,67108864,vm_jit_map,8193*8);
requires disjoint_bytes(vm_jit_errors,524288,vm_jit_map,8193*8);
requires disjoint_bytes(vm_jit_branches,8192*16,vm_jit_map,8193*8);
requires disjoint_bytes(output,67108864,bytecode,bytecode_size);
requires disjoint_bytes(vm_jit_errors,524288,bytecode,bytecode_size);
requires disjoint_bytes(vm_jit_branches,8192*16,bytecode,bytecode_size);
requires disjoint_bytes(vm_jit_map,8193*8,bytecode,bytecode_size);
requires readable_bytes(observed,8);
requires disjoint_bytes(vm_jit_map+slot*8,8,observed,8);
requires disjoint_bytes(output,67108864,observed,8);
requires disjoint_bytes(vm_jit_errors,524288,observed,8);
requires disjoint_bytes(vm_jit_branches+vm_jit_branch_count*16,16,observed,8);
modifies vm_error,output_size,native_address_site,native_address_kind,native_address_value,native_binary_cached,native_boolean_end,native_boolean_start,native_boolean_cc,vm_jit_error_count,vm_jit_branch_count,bytes(vm_jit_errors,524288),bytes(vm_jit_branches+vm_jit_branch_count*16,16),bytes(output,67108864),bytes(vm_jit_map+slot*8,8);
ensures output_size>=base && output_size<=base+256*((slot+1)-1);
ensures vm_jit_error_count>=0 && vm_jit_error_count<=3*((slot+1)-1);
ensures vm_jit_branch_count>=0 && vm_jit_branch_count<=(slot+1)-1;
ensures load64(observed)==old(load64(observed));
fn jit_emit_slot_keep_observation(bytecode,bytecode_size,pc,start,end,slots,slot,base,observed) {
    ghost let previous=load64(observed);
    jit_emit_physical_slot_from_scratch(bytecode,bytecode_size,pc,start,end,slots,slot,base);
    proof {assert load64(observed)==previous;}
}
