// Bounded writes during leaf body emission after the prologue. The checker
// uses the source loop and checked dispatch projections for arbitrary words.
// Native execution still requires the production admission predicate.
requires bytecode_size>=16 && bytecode_size<=268435456;
requires start>=0 && start<=268435440;
requires count>=1 && count<=8192;
requires end==start+count*16 && end<=bytecode_size;
requires slots>=0 && slots<=4096;
requires output_size>=21 && output_size<=57365;
requires vm_jit_error_count==0 && vm_jit_branch_count==0;
requires output_limit==67108864;
requires vm_mode==0 && native_branch_mode==0;
requires !native_register_frame || !native_reg_replay;
requires vm_restricted!=0;
requires vm_heap_used>=16 && vm_heap_used<=1000000000;
requires vm_heap>0 && vm_heap<=0x7fffffffffffffff-vm_heap_used;
requires readable_bytes(bytecode,bytecode_size);
requires writable_bytes(output,67108864);
requires writable_bytes(vm_jit_errors,524288);
requires writable_bytes(vm_jit_branches,8192*16);
requires writable_bytes(vm_jit_map,8193*8);
requires disjoint_bytes(output,67108864,vm_jit_errors,524288);
requires disjoint_bytes(output,67108864,vm_jit_branches,8192*16);
requires disjoint_bytes(vm_jit_errors,524288,vm_jit_branches,8192*16);
requires disjoint_bytes(output,67108864,vm_jit_map,8193*8);
requires disjoint_bytes(vm_jit_errors,524288,vm_jit_map,8193*8);
requires disjoint_bytes(vm_jit_branches,8192*16,vm_jit_map,8193*8);
requires disjoint_bytes(output,67108864,bytecode,bytecode_size);
requires disjoint_bytes(vm_jit_errors,524288,bytecode,bytecode_size);
requires disjoint_bytes(vm_jit_branches,8192*16,bytecode,bytecode_size);
requires disjoint_bytes(vm_jit_map,8193*8,bytecode,bytecode_size);
modifies vm_error,output_size,native_address_site,native_address_kind,native_address_value,native_binary_cached,native_boolean_end,native_boolean_start,native_boolean_cc,vm_jit_error_count,vm_jit_branch_count,bytes(vm_jit_errors,524288),bytes(vm_jit_branches,8192*16),bytes(output,67108864),bytes(vm_jit_map,8193*8);
ensures output_size>=old(output_size) && output_size<=2154261;
ensures vm_jit_error_count>=0 && vm_jit_error_count<=3*(count-1);
ensures vm_jit_branch_count>=0 && vm_jit_branch_count<=count-1;
ensures readable_bytes(bytecode,bytecode_size);
fn jit_emit_physical_body(bytecode,bytecode_size,start,end,slots,count) {
    let base=output_size;
    let pc=end;
PRODUCTION_EMISSION_LOOP_SETUP
    proof {jit_emission_map_count(start,end,count);assert map_count==count;}
    invariant map_slot>=1 && map_slot<=count;
    invariant output_size>=base && output_size<=base+256*(map_slot-1);
    invariant vm_jit_error_count>=0 && vm_jit_error_count<=3*(map_slot-1);
    invariant vm_jit_branch_count>=0 && vm_jit_branch_count<=map_slot-1;
    decreases count-map_slot;
PRODUCTION_EMISSION_LOOP_ENTRY
        proof {jit_physical_slot_bounds(start,end,bytecode_size,count,map_slot,pc);}
        ghost let branch_start=vm_jit_branch_count;
        jit_emit_physical_slot_from_scratch(bytecode,bytecode_size,pc,start,end,slots,map_slot,base);
        proof {jit_branch_prefix_advance(map_slot,branch_start,vm_jit_branch_count);}
PRODUCTION_EMISSION_LOOP_STEP
    }
    proof {
        assert map_slot==count;
        jit_emission_final_counts(map_slot,count,vm_jit_error_count,vm_jit_branch_count);
        jit_headroom_at_slot(base,map_slot,output_size);
    }
}


requires start>=0 && start<=268435440;
requires bytecode_size>=16 && bytecode_size<=268435456;
requires count>=1 && count<=8192 && end==start+count*16 && end<=bytecode_size;
requires slot>=1 && slot<count && pc==start+slot*16;
ensures pc>=start+16 && pc<end;
ensures pc>=0 && pc<=bytecode_size-16;
lemma fn jit_physical_slot_bounds(start,end,bytecode_size,count,slot,pc) {
    let relative=slot*16;
    let extent=count*16;
    assert relative>=16 && relative<=131056;
    assert extent>=16 && extent<=131072;
    assert slot+1<=count;
    assert (slot+1)*16==slot*16+16;
    assert ((slot+1)<<4)<=(count<<4);
    jit_emission_offset_add_order(start,16,relative);
    let next=pc+16;
    assert next==start+(slot+1)*16;
    jit_emission_pc_order(next,start,end,slot+1,count);
    assert pc+16<=end;
    assert pc>=0 && pc<=268566512;
    jit_emission_pc_fit(pc,end,bytecode_size);
}

requires base>=0 && base<=268435440;
requires first>=0 && first<=later && later<=131072;
ensures base+first<=base+later;
lemma fn jit_emission_offset_add_order(base,first,later) {
    let lower=base+first;
    let upper=base+later;
    assert lower>=0 && lower<=268566512;
    assert upper>=0 && upper<=268566512;
    assert upper-lower==later-first;
    assert later-first>=0;
}

requires pc>=0 && pc<=268566512;
requires pc+16<=end && end<=size && size<=268435456;
ensures pc<end && pc<=size-16;
lemma fn jit_emission_pc_fit(pc,end,size) {
    assert pc+16>pc;
    assert size-16>=0;
    assert pc<=size-16;
}

requires start>=0 && start<=268435440;
requires slot>=1 && slot<=count && count<=8192;
requires pc==start+slot*16 && end==start+count*16;
ensures pc<=end;
lemma fn jit_emission_pc_order(pc,start,end,slot,count) {
    if slot==count {assert pc==end;return 0;}
    assert slot*16==slot<<4 && count*16==count<<4;
    assert slot*16<count*16;
    assert slot*16>=16 && count*16<=131072;
    assert pc<end;
}

requires slot==count;
requires errors>=0 && errors<=3*(slot-1);
requires branches>=0 && branches<=slot-1;
ensures errors>=0 && errors<=3*(count-1);
ensures branches>=0 && branches<=count-1;
lemma fn jit_emission_final_counts(slot,count,errors,branches) {
    assert slot-1==count-1;
}

requires start>=0 && start<=268435440;
requires count>=1 && count<=8192 && end==start+count*16 && end<=268435456;
ensures (end-start)/16==count;
lemma fn jit_emission_map_count(start,end,count) {
    let extent=end-start;
    assert extent==count*16;
    assert extent>=16 && extent<=131072;
    assert extent/16==extent>>4;
    assert ((count*16)>>4)==count;
}
