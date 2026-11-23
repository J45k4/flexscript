// Each iteration can write the row at the current branch cursor. A
// range reserves the table tail starting at its entry cursor. The
// observed trace follows one selected branch across that suffix.
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
requires first_branch>=0 && first_branch<=8191;
requires vm_jit_branch_count==first_branch;
requires writable_bytes(vm_jit_branches+first_branch*16,8192*16-first_branch*16);
modifies vm_error,output_size,native_address_site,native_address_kind,native_address_value,native_binary_cached,native_boolean_end,native_boolean_start,native_boolean_cc,vm_jit_error_count,vm_jit_branch_count,bytes(vm_jit_errors,524288),bytes(vm_jit_branches+first_branch*16,8192*16-first_branch*16),bytes(output,67108864),bytes(vm_jit_map+first*8,8193*8-first*8);
ensures output_size>=old(output_size);
ensures output_size>=base && output_size<=base+256*(last-1);
ensures vm_jit_error_count>=0 && vm_jit_error_count<=3*(last-1);
ensures vm_jit_branch_count>=0 && vm_jit_branch_count<=last-1;
ensures vm_jit_branch_count>=first_branch;
ensures readable_bytes(bytecode,bytecode_size);
fn jit_emit_branch_range(bytecode,bytecode_size,start,end,slots,count,first,last,base,first_branch) {
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
    invariant vm_jit_branch_count>=first_branch;
    decreases last-map_slot;
PRODUCTION_MAP_RANGE_ENTRY
        proof {
            jit_range_enclosing_slot(map_slot,last,count);
            jit_physical_slot_bounds(start,end,bytecode_size,count,map_slot,pc);
            jit_map_tail_member(vm_jit_map,first,map_slot);
            jit_loop_slice_rank(first,map_slot,last);
            jit_record_prefix_capacity(map_slot,vm_jit_error_count,vm_jit_branch_count);
            jit_branch_tail_member(vm_jit_branches,first_branch,vm_jit_branch_count);
        }
        ghost let before=output_size;
        ghost let branch_start=vm_jit_branch_count;
        jit_emit_physical_slot_from_scratch(bytecode,bytecode_size,pc,start,end,slots,map_slot,base);
        proof {
            jit_branch_prefix_advance(map_slot,branch_start,vm_jit_branch_count);
            jit_cursor_range_keeps_lower_bound(first_branch,branch_start,vm_jit_branch_count);
        }
        proof {jit_cursor_range_keeps_lower_bound(entered,before,output_size);}
PRODUCTION_MAP_RANGE_ADVANCE
    }
    proof {
        jit_range_end_slot(map_slot,last);
        jit_emission_final_counts(map_slot,last,vm_jit_error_count,vm_jit_branch_count);
        jit_range_end_extent(base,map_slot,last,output_size);
    }
}


requires first>=0 && first<=8191;
requires writable_bytes(branches,8192*16);
ensures writable_bytes(branches+first*16,8192*16-first*16);
lemma fn jit_branch_tail_grant(branches,first) {
    let offset=first*16;
    assert offset>=0 && offset<=8191*16;
    assert 8192*16-offset>=16;
    assert writable_bytes(branches+offset,8192*16-offset);
}


requires first>=0 && first<=row && row<=8191;
requires writable_bytes(branches,8192*16);
ensures branches+row*16>=branches+first*16;
ensures (branches+row*16)-(branches+first*16)>=0;
ensures (branches+row*16)-(branches+first*16)<=8192*16-first*16-16;
lemma fn jit_branch_tail_member(branches,first,row) {
    let begin=first*16;
    let offset=row*16;
    assert begin>=0 && begin<=offset && offset<=8191*16;
    assert writable_bytes(branches+begin,16);
    assert writable_bytes(branches+offset,16);
    assert (branches+offset)-(branches+begin)==offset-begin;
    assert offset-begin>=0;
    assert offset-begin<=8192*16-begin-16;
}


requires row>=0 && row<8192;
requires writable_bytes(branches,8192*16);
requires disjoint_bytes(arena,length,branches,8192*16);
requires length==67108864 || length==524288;
ensures disjoint_bytes(arena,length,branches+row*16,8);
ensures disjoint_bytes(arena,length,branches+row*16+8,8);
lemma fn jit_branch_words_separate(arena,length,branches,row) {
    jit_branch_record_grant(branches,row);
    jit_granted_instruction_words(branches+row*16);
}


// Observe the source slot and its branch row in the body prefix ending
// at last. The same prefix serves the self-target and forward-target cases.
requires bytecode_size>=16 && bytecode_size<=268435456;
requires start>=0 && start<=268435440;
requires count>=2 && count<=8192;
requires observed>=1 && observed<count;
requires observed<last && last<=count;
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
requires pc==start+observed*16;
requires readable_bytes(bytecode+pc,8);
requires readable_bytes(bytecode+pc+8,8);
requires load64(bytecode+pc)>=10 && load64(bytecode+pc)<=12;
modifies vm_error,output_size,native_address_site,native_address_kind,native_address_value,native_binary_cached,native_boolean_end,native_boolean_start,native_boolean_cc,vm_jit_error_count,vm_jit_branch_count,bytes(vm_jit_errors,524288),bytes(vm_jit_branches,8192*16),bytes(output,67108864),bytes(vm_jit_map,8193*8);
ensures output_size>=old(output_size) && output_size<=2154261;
ensures output_size<=old(output_size)+256*(last-1);
ensures vm_jit_error_count>=0 && vm_jit_error_count<=3*(last-1);
ensures vm_jit_branch_count>=0 && vm_jit_branch_count<=last-1;
ensures readable_bytes(bytecode,bytecode_size);
ensures result>=0 && result<vm_jit_branch_count;
ensures load64(vm_jit_branches+result*16)>=old(output_size);
ensures load64(vm_jit_branches+result*16)<=output_size-4;
ensures load64(vm_jit_branches+result*16+8)==(old(load64(bytecode+pc+8))-start)/16;
ensures old(load64(bytecode+pc+8))!=pc || load64(vm_jit_branches+result*16+8)==observed;
ensures load64(vm_jit_map+observed*8)>=old(output_size);
ensures load64(vm_jit_map+observed*8)<output_size;
fn jit_emit_observed_branch(bytecode,bytecode_size,start,end,slots,count,last,observed,pc) {
    let base=output_size;
    ghost let source_op=load64(bytecode+pc);
    ghost let source_arg=load64(bytecode+pc+8);
    proof {
        jit_physical_slot_bounds(start,end,bytecode_size,count,observed,pc);
        jit_map_tail_grant(vm_jit_map,1);
        jit_branch_tail_grant(vm_jit_branches,0);
        jit_branch_input_words(output,67108864,bytecode,bytecode_size,pc);
        jit_branch_input_words(vm_jit_errors,524288,bytecode,bytecode_size,pc);
        jit_branch_input_words(vm_jit_branches,8192*16,bytecode,bytecode_size,pc);
        jit_branch_input_map_tail(vm_jit_map,1,bytecode,bytecode_size,pc);
    }
    jit_emit_branch_range(bytecode,bytecode_size,start,end,slots,count,1,observed,base,0);
    let row=vm_jit_branch_count;
    let address=vm_jit_branches+row*16;
    let beginning=output_size;
    proof {
        jit_headroom_at_slot(base,observed,beginning);
        jit_loop_slice_rank(1,observed,last);
        jit_observed_branch_index(observed,row);
        jit_branch_record_grant(vm_jit_branches,row);
        jit_granted_instruction_words(address);
        assert load64(bytecode+pc)==source_op;
        assert load64(bytecode+pc+8)==source_arg;
    }
    jit_emit_physical_slot_from_scratch(bytecode,bytecode_size,pc,start,end,slots,observed,base);
    ghost let emitted=output_size;
    let place=load64(address);
    let target=load64(address+8);
    proof {
        assert vm_jit_branch_count==row+1;
        assert place==emitted-4;
        assert target==(source_arg-start)/16;
        jit_branch_self_target_index(start,observed,pc,source_arg,target);
        assert load64(vm_jit_map+observed*8)==beginning;
    }
    jit_emit_branch_suffix_keeps_row_and_map(bytecode,bytecode_size,start,end,slots,count,observed+1,last,base,row,observed,beginning,place,target);
    proof {
        jit_headroom_at_slot(base,last,output_size);
        assert load64(address)==place;
        assert load64(address+8)==target;
        jit_branch_site_interval(base,beginning,emitted,output_size,place);
        jit_branch_observed_row_live(row,vm_jit_branch_count);
        jit_finish_branch_bounds(place,load64(vm_jit_branches+row*16),base,output_size);
        jit_finish_branch_index(target,load64(vm_jit_branches+row*16+8),(source_arg-start)/16);
        assert source_arg!=pc || load64(vm_jit_branches+row*16+8)==observed;
        assert load64(vm_jit_map+observed*8)==beginning;
        jit_observed_map_cursor(base,beginning,emitted,output_size);
        jit_finish_map_bounds(beginning,load64(vm_jit_map+observed*8),base,output_size);
    }
    return row;
}


requires observed>=1 && observed<=8191;
requires row>=0 && row<=observed-1;
ensures row<=8190;
lemma fn jit_observed_branch_index(observed,row) {
    assert observed-1<=8190;
}


requires row>=0 && row<=8190;
requires count>=row+1;
ensures row<count;
lemma fn jit_branch_observed_row_live(row,count) {
    assert row+1>row;
}


requires base<=beginning;
requires beginning>=21 && beginning<=2154261;
requires emitted>=beginning+23;
requires emitted<=final && final<=2154261;
requires site==emitted-4;
ensures site>=base;
ensures site<=final-4;
lemma fn jit_branch_site_interval(base,beginning,emitted,final,site) {
    assert beginning+23>=beginning+4;
    assert site>=beginning;
    assert site+4==emitted;
    assert emitted>=4 && emitted<=2154261;
    assert final>=4;
    assert emitted-4<=final-4;
}


requires size>=16 && size<=268435456;
requires pc>=0 && pc<=size-16;
requires readable_bytes(code,size);
requires length==67108864 || length==524288 || length==8192*16 || length==8193*8;
requires disjoint_bytes(arena,length,code,size);
ensures disjoint_bytes(arena,length,code+pc,16);
lemma fn jit_branch_input_words(arena,length,code,size,pc) {
    assert readable_bytes(code+pc,16);
    jit_granted_instruction_words(code+pc);
}


requires size>=16 && size<=268435456;
requires pc>=0 && pc<=size-16;
requires first>=1 && first<=8192;
requires readable_bytes(code,size);
requires writable_bytes(map,8193*8);
requires disjoint_bytes(map,8193*8,code,size);
ensures disjoint_bytes(map+first*8,8193*8-first*8,code+pc,16);
lemma fn jit_branch_input_map_tail(map,first,code,size,pc) {
    jit_map_tail_grant(map,first);
    assert readable_bytes(code+pc,16);
    assert disjoint_bytes(map,8193*8,code+pc,16);
}


requires row>=0 && row<8192;
requires first>=1 && first<=8192;
requires writable_bytes(branches,8192*16);
requires writable_bytes(map,8193*8);
requires disjoint_bytes(branches,8192*16,map,8193*8);
ensures disjoint_bytes(map+first*8,8193*8-first*8,branches+row*16,16);
lemma fn jit_branch_observation_map_tail(map,first,branches,row) {
    jit_map_tail_grant(map,first);
    jit_branch_record_grant(branches,row);
    assert disjoint_bytes(map,8193*8,branches+row*16,16);
    jit_granted_instruction_words(branches+row*16);
}


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
requires row>=0 && row<=8190;
requires vm_jit_branch_count>row;
requires writable_bytes(vm_jit_map+first*8,8193*8-first*8);
modifies vm_error,output_size,native_address_site,native_address_kind,native_address_value,native_binary_cached,native_boolean_end,native_boolean_start,native_boolean_cc,vm_jit_error_count,vm_jit_branch_count,bytes(vm_jit_errors,524288),bytes(vm_jit_branches,8192*16),bytes(output,67108864),bytes(vm_jit_map+first*8,8193*8-first*8);
ensures output_size>=old(output_size);
ensures output_size>=base && output_size<=base+256*(last-1);
ensures vm_jit_error_count>=0 && vm_jit_error_count<=3*(last-1);
ensures vm_jit_branch_count>=0 && vm_jit_branch_count<=last-1;
ensures vm_jit_branch_count>=row+1;
ensures readable_bytes(bytecode,bytecode_size);
ensures load64(vm_jit_branches+row*16)==old(load64(vm_jit_branches+row*16));
ensures load64(vm_jit_branches+row*16+8)==old(load64(vm_jit_branches+row*16+8));
fn jit_emit_branch_suffix_keeps_row(bytecode,bytecode_size,start,end,slots,count,first,last,base,row) {
    let site=vm_jit_branches+row*16;
    let first_branch=vm_jit_branch_count;
    proof {
        jit_branch_row_before_range(vm_jit_branches,row,first_branch);
        jit_branch_words_separate(output,67108864,vm_jit_branches,row);
        jit_branch_words_separate(vm_jit_errors,524288,vm_jit_branches,row);
        jit_branch_observation_map_tail(vm_jit_map,first,vm_jit_branches,row);
    }
    ghost let target=load64(site+8);
    ghost let at=load64(site);
    jit_emit_branch_range(bytecode,bytecode_size,start,end,slots,count,first,last,base,first_branch);
    proof {
        jit_retained_branch_count(row,first_branch,vm_jit_branch_count);
        assert load64(site)==at;
        assert load64(site+8)==target;
    }
}

requires place==recorded;
requires place>=beginning;
requires place<=final-4;
ensures recorded>=beginning;
ensures recorded<=final-4;
lemma fn jit_finish_branch_bounds(place,recorded,beginning,final) {}

requires target==recorded;
requires expected==target;
ensures recorded==expected;
lemma fn jit_finish_branch_index(target,recorded,expected) {}


// Keep the recorded cursor available as a scalar across suffix emission.
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
requires row>=0 && row<=8190;
requires vm_jit_branch_count>row;
requires seen>=1 && seen<=8191;
requires seen<first;
requires readable_bytes(vm_jit_map+seen*8,8);
requires load64(vm_jit_map+seen*8)==recorded;
requires readable_bytes(vm_jit_branches+row*16,8);
requires readable_bytes(vm_jit_branches+row*16+8,8);
requires load64(vm_jit_branches+row*16)==place;
requires load64(vm_jit_branches+row*16+8)==target;
modifies vm_error,output_size,native_address_site,native_address_kind,native_address_value,native_binary_cached,native_boolean_end,native_boolean_start,native_boolean_cc,vm_jit_error_count,vm_jit_branch_count,bytes(vm_jit_errors,524288),bytes(vm_jit_branches,8192*16),bytes(output,67108864),bytes(vm_jit_map,8193*8);
ensures output_size>=old(output_size);
ensures output_size>=base && output_size<=base+256*(last-1);
ensures vm_jit_error_count>=0 && vm_jit_error_count<=3*(last-1);
ensures vm_jit_branch_count>=0 && vm_jit_branch_count<=last-1;
ensures vm_jit_branch_count>=row+1;
ensures readable_bytes(bytecode,bytecode_size);
ensures load64(vm_jit_branches+row*16)==place;
ensures load64(vm_jit_branches+row*16+8)==target;
ensures load64(vm_jit_map+seen*8)==recorded;
fn jit_emit_branch_suffix_keeps_row_and_map(bytecode,bytecode_size,start,end,slots,count,first,last,base,row,seen,recorded,place,target) {
    proof {
        jit_map_word_before_range(vm_jit_map,seen,first);
        jit_map_scratch_separate(output,67108864,vm_jit_map,seen);
        jit_map_scratch_separate(vm_jit_errors,524288,vm_jit_map,seen);
        jit_map_scratch_separate(vm_jit_branches,8192*16,vm_jit_map,seen);
    }

    jit_emit_branch_suffix_keeps_row(bytecode,bytecode_size,start,end,slots,count,first,last,base,row);
    proof {
        assert load64(vm_jit_branches+row*16)==place;
        assert load64(vm_jit_branches+row*16+8)==target;
        assert load64(vm_jit_map+seen*8)==recorded;
    }
}

requires start>=0 && start<=268435440;
requires observed>=1 && observed<=8191;
requires pc==start+observed*16 && pc>=0 && pc<268435456;
requires index==(arg-start)/16;
ensures arg!=pc || index==observed;
lemma fn jit_branch_self_target_index(start,observed,pc,arg,index) {
    if arg==pc {
        assert arg-start==observed*16;
        assert observed*16>=16 && observed*16<=131056;
        assert (observed*16)/16==observed;
    }
}

requires recorded==mapped;
requires recorded>=base && recorded<final;
ensures mapped>=base;
ensures mapped<final;
lemma fn jit_finish_map_bounds(recorded,mapped,base,final) {}

// Preserve the map word for an earlier target while emitting the source branch.
requires bytecode_size>=16 && bytecode_size<=268435456;
requires start>=0 && start<=268435440;
requires count>=2 && count<=8192;
requires observed>=1 && observed<count;
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
requires pc==start+observed*16;
requires readable_bytes(bytecode+pc,8);
requires readable_bytes(bytecode+pc+8,8);
requires load64(bytecode+pc)>=10 && load64(bytecode+pc)<=12;
requires destination>=1 && destination<observed;
requires load64(bytecode+pc+8)==start+destination*16;
modifies vm_error,output_size,native_address_site,native_address_kind,native_address_value,native_binary_cached,native_boolean_end,native_boolean_start,native_boolean_cc,vm_jit_error_count,vm_jit_branch_count,bytes(vm_jit_errors,524288),bytes(vm_jit_branches,8192*16),bytes(output,67108864),bytes(vm_jit_map,8193*8);
ensures output_size>=old(output_size) && output_size<=2154261;
ensures vm_jit_error_count>=0 && vm_jit_error_count<=3*(count-1);
ensures vm_jit_branch_count>=0 && vm_jit_branch_count<=count-1;
ensures readable_bytes(bytecode,bytecode_size);
ensures result>=0 && result<vm_jit_branch_count;
ensures load64(vm_jit_branches+result*16)>=old(output_size);
ensures load64(vm_jit_branches+result*16)<=output_size-4;
ensures load64(vm_jit_branches+result*16+8)==(old(load64(bytecode+pc+8))-start)/16;
ensures load64(vm_jit_branches+result*16+8)==destination;
ensures load64(vm_jit_map+destination*8)>=old(output_size);
ensures load64(vm_jit_map+destination*8)<output_size;
fn jit_emit_observed_earlier_target(bytecode,bytecode_size,start,end,slots,count,observed,pc,destination) {
    let base=output_size;
    ghost let source_op=load64(bytecode+pc);
    ghost let source_arg=load64(bytecode+pc+8);
    proof {
        jit_physical_slot_bounds(start,end,bytecode_size,count,observed,pc);
        jit_order_trace_slots(destination,observed,count);
        jit_physical_slot_bounds(start,end,bytecode_size,count,destination,start+destination*16);
        jit_branch_input_words(output,67108864,bytecode,bytecode_size,pc);
        jit_branch_input_words(vm_jit_errors,524288,bytecode,bytecode_size,pc);
        jit_branch_input_words(vm_jit_branches,8192*16,bytecode,bytecode_size,pc);
        jit_branch_input_words(vm_jit_map,8193*8,bytecode,bytecode_size,pc);
    }
    let recorded=jit_emit_observed_body(bytecode,bytecode_size,start,end,slots,count,observed,destination);
    proof {
        assert load64(vm_jit_map+destination*8)==recorded;
    }
    let row=vm_jit_branch_count;
    let address=vm_jit_branches+row*16;
    proof {
        jit_headroom_at_slot(base,observed,output_size);
        jit_loop_slice_rank(1,observed,count);
        jit_observed_branch_index(observed,row);
        jit_branch_record_grant(vm_jit_branches,row);
        jit_granted_instruction_words(address);
        jit_map_word_before_tail(vm_jit_map,destination);
        jit_map_scratch_separate(output,67108864,vm_jit_map,destination);
        jit_map_scratch_separate(vm_jit_errors,524288,vm_jit_map,destination);
        jit_branch_map_slots_separate(vm_jit_branches,row,vm_jit_map,destination);
        jit_record_map_ordered_words(vm_jit_map,destination,observed);
        assert load64(bytecode+pc)==source_op;
        assert load64(bytecode+pc+8)==source_arg;
    }
    jit_emit_selected_slot_keep_map(bytecode,bytecode_size,pc,start,end,slots,observed,base,vm_jit_map+destination*8,recorded);
    ghost let emitted=output_size;
    let place=load64(address);
    let target=load64(address+8);
    proof {
        assert vm_jit_branch_count==row+1;
        assert place==emitted-4;
        assert target==(source_arg-start)/16;
        jit_branch_self_target_index(start,destination,start+destination*16,source_arg,target);
        assert load64(vm_jit_map+destination*8)==recorded;
        assert place>=base;
        assert output_size>=base && output_size<=base+256*((observed+1)-1);
        assert vm_jit_error_count>=0 && vm_jit_error_count<=3*((observed+1)-1);
    }
    jit_emit_branch_suffix_keeps_row_and_map(bytecode,bytecode_size,start,end,slots,count,observed+1,count,base,row,destination,recorded,place,target);
    proof {
        jit_headroom_at_slot(base,count,output_size);
        assert load64(address)==place;
        assert load64(address+8)==target;
        jit_retained_branch_site(base,place,emitted,emitted,output_size);
        jit_branch_observed_row_live(row,vm_jit_branch_count);
        jit_finish_branch_bounds(place,load64(vm_jit_branches+row*16),base,output_size);
        jit_finish_branch_index(target,load64(vm_jit_branches+row*16+8),(source_arg-start)/16);
        assert load64(vm_jit_branches+row*16+8)==destination;
        jit_prior_map_offset(base,recorded,emitted,output_size);
        jit_finish_map_bounds(recorded,load64(vm_jit_map+destination*8),base,output_size);
    }
    return row;
}

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
requires readable_bytes(bytecode+pc,8);
requires readable_bytes(bytecode+pc+8,8);
requires load64(bytecode+pc)>=10 && load64(bytecode+pc)<=12;
requires readable_bytes(observed,8);
requires load64(observed)==recorded;
requires jit_observed_offset_in_body(base,recorded,output_size);
requires disjoint_bytes(vm_jit_map+slot*8,8,observed,8);
requires disjoint_bytes(output,67108864,observed,8);
requires disjoint_bytes(vm_jit_errors,524288,observed,8);
requires disjoint_bytes(vm_jit_branches+vm_jit_branch_count*16,16,observed,8);
modifies vm_error,output_size,native_address_site,native_address_kind,native_address_value,native_binary_cached,native_boolean_end,native_boolean_start,native_boolean_cc,vm_jit_error_count,vm_jit_branch_count,bytes(vm_jit_errors,524288),bytes(vm_jit_branches+vm_jit_branch_count*16,16),bytes(output,67108864),bytes(vm_jit_map+slot*8,8);
ensures output_size>=base && output_size<=base+256*((slot+1)-1);
ensures vm_jit_error_count>=0 && vm_jit_error_count<=3*((slot+1)-1);
ensures vm_jit_branch_count==old(vm_jit_branch_count)+1;
ensures vm_jit_branch_count>=0 && vm_jit_branch_count<=(slot+1)-1;
ensures load64(observed)==old(recorded);
ensures output_size>=old(output_size);
ensures output_size>=old(output_size)+23;
ensures output_size<=2154261;
ensures jit_observed_offset_in_body(base,old(recorded),output_size);
ensures load64(vm_jit_branches+old(vm_jit_branch_count)*16)==output_size-4;
ensures load64(vm_jit_branches+old(vm_jit_branch_count)*16)>=base;
ensures load64(vm_jit_branches+old(vm_jit_branch_count)*16+8)==(old(load64(bytecode+pc+8))-start)/16;
fn jit_emit_selected_slot_keep_map(bytecode,bytecode_size,pc,start,end,slots,slot,base,observed,recorded) {
    ghost let began=output_size;
    ghost let row=vm_jit_branch_count;
    ghost let arg=load64(bytecode+pc+8);
    jit_emit_physical_slot_from_scratch(bytecode,bytecode_size,pc,start,end,slots,slot,base);
    proof {
        jit_headroom_at_slot(base,slot,began);
        jit_headroom_at_slot(base,slot+1,output_size);
        jit_prior_map_offset(base,recorded,began,output_size);
        assert vm_jit_branch_count==row+1;
        assert load64(observed)==recorded;
        assert load64(vm_jit_branches+row*16)==output_size-4;
        jit_branch_site_interval(base,began,output_size,output_size,load64(vm_jit_branches+row*16));
        assert load64(vm_jit_branches+row*16+8)==(arg-start)/16;
    }
}

requires jit_observed_offset_in_body(base,recorded,prefix);
requires prefix<=final;
ensures jit_observed_offset_in_body(base,recorded,final);
lemma fn jit_prior_map_offset(base,recorded,prefix,final) {
    assert recorded<final;
}

// Follow the source row through the target slot and the remaining body.
requires bytecode_size>=16 && bytecode_size<=268435456;
requires start>=0 && start<=268435440;
requires count>=2 && count<=8192;
requires observed>=1 && observed<count;
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
requires pc==start+observed*16;
requires readable_bytes(bytecode+pc,8);
requires readable_bytes(bytecode+pc+8,8);
requires load64(bytecode+pc)>=10 && load64(bytecode+pc)<=12;
requires destination>observed && destination<count;
requires load64(bytecode+pc+8)==start+destination*16;
modifies vm_error,output_size,native_address_site,native_address_kind,native_address_value,native_binary_cached,native_boolean_end,native_boolean_start,native_boolean_cc,vm_jit_error_count,vm_jit_branch_count,bytes(vm_jit_errors,524288),bytes(vm_jit_branches,8192*16),bytes(output,67108864),bytes(vm_jit_map,8193*8);
ensures output_size>=old(output_size) && output_size<=2154261;
ensures vm_jit_error_count>=0 && vm_jit_error_count<=3*(count-1);
ensures vm_jit_branch_count>=0 && vm_jit_branch_count<=count-1;
ensures readable_bytes(bytecode,bytecode_size);
ensures result>=0 && result<vm_jit_branch_count;
ensures load64(vm_jit_branches+result*16)>=old(output_size);
ensures load64(vm_jit_branches+result*16)<=output_size-4;
ensures load64(vm_jit_branches+result*16+8)==(old(load64(bytecode+pc+8))-start)/16;
ensures load64(vm_jit_branches+result*16+8)==destination;
ensures load64(vm_jit_map+destination*8)>=old(output_size);
ensures load64(vm_jit_map+destination*8)<output_size;
fn jit_emit_observed_later_target(bytecode,bytecode_size,start,end,slots,count,observed,pc,destination) {
    let base=output_size;
    ghost let source_arg=load64(bytecode+pc+8);
    let target_pc=start+destination*16;
    proof {
        jit_order_trace_slots(observed,destination,count);
        jit_physical_slot_bounds(start,end,bytecode_size,count,destination,target_pc);
    }
    let row=jit_emit_observed_branch(bytecode,bytecode_size,start,end,slots,count,destination,observed,pc);
    let recorded=output_size;
    let place=load64(vm_jit_branches+row*16);
    let target=load64(vm_jit_branches+row*16+8);
    proof {
        jit_headroom_at_slot(base,destination,recorded);
        jit_observed_row_in_table(destination,row,vm_jit_branch_count);
        jit_branch_record_grant(vm_jit_branches,row);
        jit_granted_instruction_words(vm_jit_branches+row*16);
        jit_loop_slice_rank(1,destination,count);
        jit_branch_self_target_index(start,destination,target_pc,source_arg,target);
    }
    jit_emit_target_slot_keep_row(bytecode,bytecode_size,target_pc,start,end,slots,destination,base,row,place,target);
    ghost let target_end=output_size;
    proof {
        assert load64(vm_jit_branches+row*16)==place;
        assert load64(vm_jit_branches+row*16+8)==target;
        assert load64(vm_jit_map+destination*8)==recorded;
        jit_frame_after_selected_slot(base,destination,output_size,vm_jit_error_count,vm_jit_branch_count);
    }
    jit_emit_branch_suffix_keeps_row_and_map(bytecode,bytecode_size,start,end,slots,count,destination+1,count,base,row,destination,recorded,place,target);
    proof {
        jit_headroom_at_slot(base,count,output_size);
        assert load64(vm_jit_branches+row*16)==place;
        assert load64(vm_jit_branches+row*16+8)==target;
        jit_branch_observed_row_live(row,vm_jit_branch_count);
        jit_retained_branch_site(base,place,recorded,target_end,output_size);
        jit_finish_branch_bounds(place,load64(vm_jit_branches+row*16),base,output_size);
        jit_finish_branch_index(target,load64(vm_jit_branches+row*16+8),(source_arg-start)/16);
        assert load64(vm_jit_branches+row*16+8)==destination;
        jit_observed_map_cursor(base,recorded,target_end,output_size);
        jit_finish_map_bounds(recorded,load64(vm_jit_map+destination*8),base,output_size);
    }
    return row;
}

// Record the later target while preserving the selected source row.
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
requires row>=0 && row<vm_jit_branch_count;
requires readable_bytes(vm_jit_branches+row*16,8);
requires readable_bytes(vm_jit_branches+row*16+8,8);
requires load64(vm_jit_branches+row*16)==place;
requires load64(vm_jit_branches+row*16+8)==target;
modifies vm_error,output_size,native_address_site,native_address_kind,native_address_value,native_binary_cached,native_boolean_end,native_boolean_start,native_boolean_cc,vm_jit_error_count,vm_jit_branch_count,bytes(vm_jit_errors,524288),bytes(vm_jit_branches+vm_jit_branch_count*16,16),bytes(output,67108864),bytes(vm_jit_map+slot*8,8);
ensures output_size>=base && output_size<=base+256*slot;
ensures output_size>=old(output_size)+23;
ensures vm_jit_error_count>=0 && vm_jit_error_count<=3*slot;
ensures vm_jit_branch_count>row && vm_jit_branch_count<=slot;
ensures load64(vm_jit_branches+row*16)==place;
ensures load64(vm_jit_branches+row*16+8)==target;
ensures load64(vm_jit_map+slot*8)==old(output_size);
fn jit_emit_target_slot_keep_row(bytecode,bytecode_size,pc,start,end,slots,slot,base,row,place,target) {
    let first_branch=vm_jit_branch_count;
    let address=vm_jit_branches+row*16;
    proof {
        jit_branch_row_before_range(vm_jit_branches,row,first_branch);
        jit_branch_words_separate(output,67108864,vm_jit_branches,row);
        jit_branch_words_separate(vm_jit_errors,524288,vm_jit_branches,row);
        jit_branch_words_separate_from_map_slot(vm_jit_branches,row,vm_jit_map,slot);
        jit_map_word_before_tail(vm_jit_map,slot);
    }
    ghost let before=output_size;
    jit_emit_physical_slot_from_scratch(bytecode,bytecode_size,pc,start,end,slots,slot,base);
    proof {
        assert load64(address)==place;
        assert load64(address+8)==target;
        jit_retained_branch_count(row,first_branch,vm_jit_branch_count);
        assert load64(vm_jit_map+slot*8)==before;
    }
}

requires row>=0 && row<first && first<=8191;
requires writable_bytes(branches,8192*16);
ensures readable_bytes(branches+row*16,8);
ensures readable_bytes(branches+row*16+8,8);
ensures writable_bytes(branches+first*16,8192*16-first*16);
ensures disjoint_bytes(branches+row*16,8,branches+first*16,8192*16-first*16);
ensures disjoint_bytes(branches+row*16+8,8,branches+first*16,8192*16-first*16);
ensures disjoint_bytes(branches+row*16,8,branches+first*16,16);
ensures disjoint_bytes(branches+row*16+8,8,branches+first*16,16);
lemma fn jit_branch_row_before_range(branches,row,first) {
    let before=row*16;
    let after=first*16;
    assert before>=0 && before<=8190*16 && after<=8191*16;
    jit_pair_index_distance(row,first);
    assert writable_bytes(branches+before,8);
    assert writable_bytes(branches+before+8,8);
    assert writable_bytes(branches+after,8192*16-after);
    assert writable_bytes(branches+after,16);
    assert (branches+after)-(branches+before)==(first-row)*16;
    assert (branches+after)-(branches+before+8)==(first-row)*16-8;
}

requires row>=0 && row<8192;
requires slot>=1 && slot<=8191;
requires writable_bytes(branches,8192*16);
requires writable_bytes(map,8193*8);
requires disjoint_bytes(branches,8192*16,map,8193*8);
ensures disjoint_bytes(branches+row*16,8,map+slot*8,8);
ensures disjoint_bytes(branches+row*16+8,8,map+slot*8,8);
lemma fn jit_branch_words_separate_from_map_slot(branches,row,map,slot) {
    assert row*16>=0 && row*16<=8191*16;
    assert slot*8>=8 && slot*8<=8191*8;
    assert writable_bytes(branches+row*16,8);
    assert writable_bytes(branches+row*16+8,8);
    assert writable_bytes(map+slot*8,8);
}

requires before>=0 && before<after && after<=8192;
ensures after-before>=1 && after-before<=8192;
ensures (after-before)*8>=8;
ensures (after-before)*16>=16;
ensures (after-before)*16-8>=8;
lemma fn jit_pair_index_distance(before,after) {
    let steps=after-before;
    assert steps>=1 && steps<=8192;
}

requires row>=0 && row<first && first<=8191;
requires after>=first;
ensures after>=row+1 && after>row;
lemma fn jit_retained_branch_count(row,first,after) {
    assert row+1<=first;
}

requires observed>=1 && observed<last && last<=count && count<=8192;
ensures observed<count;
ensures observed>=1 && observed<=count;
lemma fn jit_order_trace_slots(observed,last,count) {}

requires end_slot>=2 && end_slot<=8192;
requires branches>=0 && branches<=end_slot-1;
requires row>=0 && row<branches;
ensures row<8192;
lemma fn jit_observed_row_in_table(end_slot,row,branches) {}

requires slot>=1 && slot<=8191;
requires current>=base && current<=base+256*slot;
requires errors>=0 && errors<=3*slot;
requires branches>=0 && branches<=slot;
ensures current>=base && current<=base+256*((slot+1)-1);
ensures errors>=0 && errors<=3*((slot+1)-1);
ensures branches>=0 && branches<=(slot+1)-1;
lemma fn jit_frame_after_selected_slot(base,slot,current,errors,branches) {}

requires base>=21 && base<=57365;
requires site>=base && site<=prefix-4;
requires prefix>=base && prefix<=emitted && emitted<=final && final<=2154261;
ensures site>=base && site<=final-4;
lemma fn jit_retained_branch_site(base,site,prefix,emitted,final) {
    assert prefix-4<=final-4;
}
