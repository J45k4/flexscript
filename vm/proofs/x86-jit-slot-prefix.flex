// Advance the staging cursor and relocation count invariants for one slot.
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
requires writable_bytes(output,67108864);
requires writable_bytes(vm_jit_errors,524288);
requires writable_bytes(vm_jit_branches,8192*16);
requires disjoint_bytes(output,67108864,vm_jit_errors,524288);
requires disjoint_bytes(output,67108864,vm_jit_branches,8192*16);
requires disjoint_bytes(vm_jit_errors,524288,vm_jit_branches,8192*16);
modifies vm_error,output_size,native_address_site,native_address_kind,native_address_value,native_binary_cached,native_boolean_end,native_boolean_start,native_boolean_cc,vm_jit_error_count,vm_jit_branch_count,bytes(vm_jit_errors,524288),bytes(vm_jit_branches+vm_jit_branch_count*16,16),bytes(output,67108864);
ensures output_size>=base && output_size<=base+256*((slot+1)-1);
ensures vm_jit_error_count>=0 && vm_jit_error_count<=3*((slot+1)-1);
ensures vm_jit_branch_count>=0 && vm_jit_branch_count<=(slot+1)-1;
ensures ((op==5 || op==6) && (arg<16 || arg>vm_heap_used-8)) || vm_error==old(vm_error);
fn jit_emit_slot_preserves_prefix(op,arg,pc,start,slot,base) {
    ghost let cursor=output_size;
    ghost let errors=vm_jit_error_count;
    ghost let branches=vm_jit_branch_count;
    proof {
        jit_headroom_at_slot(base,slot,cursor);
        jit_record_prefix_capacity(slot,errors,branches);
    }
    jit_emit_all_metered(op,arg,pc,start);
    proof {
        jit_headroom_next_slot(base,slot,cursor,output_size);
        jit_record_prefix_step(slot,errors,branches,vm_jit_error_count,vm_jit_branch_count);
    }
}
