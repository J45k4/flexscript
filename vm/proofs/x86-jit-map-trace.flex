// Check an arbitrary observation in the production body loop. Its prefix
// and suffix use the same slot step over ascending adjacent index ranges.
// The suffix's map frame starts after the observed slot.
requires bytecode_size>=16 && bytecode_size<=268435456;
requires start>=0 && start<=268435440;
requires count>=1 && count<=8192;
requires end==start+count*16 && end<=bytecode_size;
requires slots>=0 && slots<=4096;
requires base>=21 && base<=57365;
requires first>=1 && first<=last && last<=count;
requires output_size>=base && output_size<=base+256*(first-1);
requires vm_jit_error_count>=0 && vm_jit_error_count<=3*(first-1);
requires vm_jit_branch_count>=0 && vm_jit_branch_count<=first-1;
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
requires writable_bytes(vm_jit_map+first*8,8193*8-first*8);
modifies vm_error,output_size,native_address_site,native_address_kind,native_address_value,native_binary_cached,native_boolean_end,native_boolean_start,native_boolean_cc,vm_jit_error_count,vm_jit_branch_count,bytes(vm_jit_errors,524288),bytes(vm_jit_branches,8192*16),bytes(output,67108864),bytes(vm_jit_map+first*8,8193*8-first*8);
ensures output_size>=old(output_size);
ensures output_size>=base && output_size<=base+256*(last-1);
ensures vm_jit_error_count>=0 && vm_jit_error_count<=3*(last-1);
ensures vm_jit_branch_count>=0 && vm_jit_branch_count<=last-1;
ensures readable_bytes(bytecode,bytecode_size);
fn jit_emit_body_range(bytecode,bytecode_size,start,end,slots,count,first,last,base) {
    let pc=end;
PRODUCTION_MAP_RANGE_START
    ghost let entered=output_size;
    invariant map_slot>=first;
    invariant map_slot>=1;
    invariant map_slot<=last;
    invariant output_size>=entered;
    invariant output_size>=base && output_size<=base+256*(map_slot-1);
    invariant vm_jit_error_count>=0 && vm_jit_error_count<=3*(map_slot-1);
    invariant vm_jit_branch_count>=0 && vm_jit_branch_count<=map_slot-1;
    decreases last-map_slot;
PRODUCTION_MAP_RANGE_ENTRY
        proof {
            jit_range_enclosing_slot(map_slot,last,count);
            jit_physical_slot_bounds(start,end,bytecode_size,count,map_slot,pc);
            jit_map_tail_member(vm_jit_map,first,map_slot);
            jit_loop_slice_rank(first,map_slot,last);
        }
        ghost let before=output_size;
        ghost let branch_start=vm_jit_branch_count;
        jit_emit_physical_slot_from_scratch(bytecode,bytecode_size,pc,start,end,slots,map_slot,base);
        proof {jit_branch_prefix_advance(map_slot,branch_start,vm_jit_branch_count);}
        proof {jit_cursor_range_keeps_lower_bound(entered,before,output_size);}
PRODUCTION_MAP_RANGE_ADVANCE
    }
    proof {
        jit_range_end_slot(map_slot,last);
        jit_emission_final_counts(map_slot,last,vm_jit_error_count,vm_jit_branch_count);
        jit_range_end_extent(base,map_slot,last,output_size);
    }
}


requires first>=1 && first<=8192;
requires writable_bytes(map,8193*8);
ensures writable_bytes(map+first*8,8193*8-first*8);
lemma fn jit_map_tail_grant(map,first) {
    let offset=first*8;
    assert offset>=8 && offset<=8192*8;
    assert 8193*8-offset>=8;
    assert writable_bytes(map+offset,8193*8-offset);
}

requires first>=1 && first<=slot && slot<=8191;
requires writable_bytes(map,8193*8);
ensures map+slot*8>=map+first*8;
ensures (map+slot*8)-(map+first*8)>=0;
ensures (map+slot*8)-(map+first*8)<=8193*8-first*8-8;
lemma fn jit_map_tail_member(map,first,slot) {
    let origin=first*8;
    let offset=slot*8;
    assert origin>=8 && origin<=offset && offset<=8191*8;
    assert writable_bytes(map+origin,8);
    assert writable_bytes(map+offset,8);
    assert (map+offset)-(map+origin)==offset-origin;
    assert offset-origin>=0;
    assert offset-origin<=8193*8-origin-8;
}


requires first>=1 && first<=slot && slot<last && last<=8192;
ensures slot+1>=first && slot+1<=last;
lemma fn jit_loop_slice_rank(first,slot,last) {
    assert slot+1<=last;
    assert slot+1>=slot;
}

requires seen>=1 && seen<first && first<=8192;
requires writable_bytes(map,8193*8);
ensures readable_bytes(map+seen*8,8);
ensures writable_bytes(map+first*8,8193*8-first*8);
ensures disjoint_bytes(map+seen*8,8,map+first*8,8193*8-first*8);
lemma fn jit_map_word_before_range(map,seen,first) {
    let before=seen*8;
    let after=first*8;
    assert before>=8 && before<=8191*8 && after<=8192*8;
    jit_pair_index_distance(seen,first);
    assert writable_bytes(map+before,8);
    jit_map_tail_grant(map,first);
    assert (map+after)-(map+before)==(first-seen)*8;
}

requires seen>=1 && seen<=8191;
requires writable_bytes(map,8193*8);
ensures readable_bytes(map+seen*8,8);
ensures writable_bytes(map+(seen+1)*8,8193*8-(seen+1)*8);
ensures disjoint_bytes(map+seen*8,8,map+(seen+1)*8,8193*8-(seen+1)*8);
lemma fn jit_map_word_before_tail(map,seen) {
    jit_map_word_before_range(map,seen,seen+1);
}


requires bytecode_size>=16 && bytecode_size<=268435456;
requires start>=0 && start<=268435440;
requires count>=2 && count<=8192;
requires observed>=1 && observed<last && last<=count;
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
ensures output_size<=old(output_size)+256*(last-1);
ensures vm_jit_error_count>=0 && vm_jit_error_count<=3*(last-1);
ensures vm_jit_branch_count>=0 && vm_jit_branch_count<=last-1;
ensures readable_bytes(bytecode,bytecode_size);
ensures load64(vm_jit_map+observed*8)==result;
ensures jit_observed_offset_in_body(old(output_size),result,output_size);
fn jit_emit_observed_body(bytecode,bytecode_size,start,end,slots,count,last,observed) {
    let base=output_size;
    proof {
        jit_map_tail_grant(vm_jit_map,1);
        jit_order_trace_slots(observed,last,count);
    }
    jit_emit_body_range(bytecode,bytecode_size,start,end,slots,count,1,observed,base);
    let recorded=output_size;
PRODUCTION_OBSERVED_PC
    proof {
        jit_physical_slot_bounds(start,end,bytecode_size,count,observed,pc);
        jit_headroom_at_slot(base,observed,recorded);
        jit_loop_slice_rank(1,observed,last);
        jit_map_word_before_tail(vm_jit_map,observed);
        jit_map_scratch_separate(output,67108864,vm_jit_map,observed);
        jit_map_scratch_separate(vm_jit_errors,524288,vm_jit_map,observed);
        jit_map_scratch_separate(vm_jit_branches,8192*16,vm_jit_map,observed);
    }
    jit_emit_physical_slot_from_scratch(bytecode,bytecode_size,pc,start,end,slots,observed,base);
    proof {assert load64(vm_jit_map+observed*8)==recorded;}
    ghost let emitted=output_size;
    jit_emit_body_range(bytecode,bytecode_size,start,end,slots,count,observed+1,last,base);
    proof {
        jit_observed_map_cursor(base,recorded,emitted,output_size);
        jit_headroom_at_slot(base,last,output_size);
        assert load64(vm_jit_map+observed*8)==recorded;
    }
    return recorded;
}

spec fn jit_observed_offset_in_body(base,recorded,cursor) {
    return base<=recorded && recorded<cursor;
}

requires slot>=1;
requires slot<last;
requires last<=count && count<=8192;
ensures slot<count && slot<8192;
ensures last<=8192;
lemma fn jit_range_enclosing_slot(slot,last,count) {
    assert slot<count;
    assert slot<8192;
}

requires entered<=before;
requires before<=after;
ensures entered<=after;
lemma fn jit_cursor_range_keeps_lower_bound(entered,before,after) {
    assert entered<=after;
}

requires slot<=last;
requires slot>=last;
ensures slot==last;
lemma fn jit_range_end_slot(slot,last) {
    assert slot==last;
}

requires base<=recorded;
requires recorded>=21 && recorded<=2154261;
requires emitted>=recorded+23;
requires emitted<=final;
ensures base<=recorded && recorded<final;
lemma fn jit_observed_map_cursor(base,recorded,emitted,final) {
    assert recorded+23>recorded;
    assert recorded<emitted;
    assert recorded<final;
}

requires slot==last;
requires current<=base+256*(slot-1);
ensures current<=base+256*(last-1);
lemma fn jit_range_end_extent(base,slot,last,current) {
    assert slot-1==last-1;
    assert 256*(slot-1)==256*(last-1);
}
