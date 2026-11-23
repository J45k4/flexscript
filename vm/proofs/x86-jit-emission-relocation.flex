// Carry the row for a branch to its own slot from staging through both
// production relocation passes. The exit trailer follows the body, so the
// map entry for that slot continues to identify the start of its native code.
requires bytecode_size>=16 && bytecode_size<=268435456;
requires start>=0 && start<=268435440 && start%16==0;
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
requires pc==start+observed*16 && pc%16==0;
requires readable_bytes(bytecode+pc,8);
requires readable_bytes(bytecode+pc+8,8);
requires load64(bytecode+pc)>=10 && load64(bytecode+pc)<=12;
requires load64(bytecode+pc+8)==pc;
requires output>0 && output<=0x7fffffffffffffff-67108864;
modifies vm_error,output_size,output_limit,native_address_site,native_address_kind,native_address_value,native_binary_cached,native_boolean_end,native_boolean_start,native_boolean_cc,vm_jit_error_count,vm_jit_branch_count,watched_row,watched_site,watched_index,watched_target,watched_bits,bytes(vm_jit_errors,524288),bytes(vm_jit_branches,8192*16),bytes(output,67108864),bytes(vm_jit_map,8193*8);
ensures result==0 || result==1;
ensures output_limit==bytecode_limit;
ensures result==0 || watched_index==observed;
ensures result==0 || load64(vm_jit_map+observed*8)==watched_target;
ensures result==0 || watched_site+4+((jit_rel32_bits(output+watched_site)<<32)>>32)==watched_target;
ensures result==0 || watched_site>=1 && watched_site<=output_size-4;
ensures result==0 || watched_target>=0 && watched_target<output_size;
ensures result==0 || output_size>=5 && output_size<=2154371;
ensures result==0 || jit_rel32_bits(output+watched_site)==((watched_target-watched_site-4)&4294967295);
fn jit_emit_and_relocate_self_branch(bytecode,bytecode_size,start,end,slots,count,observed,pc,bytecode_limit) {
    let base=output_size;
    let op=load64(bytecode+pc);
    let arg=load64(bytecode+pc+8);
    proof {
        jit_physical_slot_bounds(start,end,bytecode_size,count,observed,pc);
        jit_relocation_self_operand(arg,pc,start,end);
    }
    let row=jit_emit_observed_branch(bytecode,bytecode_size,start,end,slots,count,count,observed,pc);
    let record=vm_jit_branches+row*16;
    let site=load64(record);
    let target_index=load64(record+8);
    let native_target=load64(vm_jit_map+observed*8);
    ghost let body_end=output_size;
    proof {
        jit_branch_self_target_index(start,observed,pc,arg,(arg-start)/16);
        jit_relocation_table_counts(count,row,vm_jit_branch_count,vm_jit_error_count);
        jit_branch_record_grant(vm_jit_branches,row);
        jit_granted_instruction_words(record);
        jit_map_word_before_tail(vm_jit_map,observed);
        jit_branch_words_separate(output,67108864,vm_jit_branches,row);
        jit_map_scratch_separate(output,67108864,vm_jit_map,observed);
        assert target_index==observed;
        assert site>=base && site<=body_end-4;
        assert native_target>=base && native_target<body_end;
    }
    let failure=jit_emit_exit_handlers(0);
    let fuel=failure+22;
    let division=failure+44;
    let bounds=failure+66;
    let timeout=failure+88;
PRODUCTION_RESTORE_BYTECODE_LIMIT
    proof {
        jit_exit_relocation_layout(base,body_end,output_size,site,native_target);
        jit_relocation_prefix_address(output,output_size);
        jit_relocation_branch_opcode(op);
        jit_relocation_scratch_spans(output,output_size,vm_jit_branches,vm_jit_branch_count,vm_jit_errors,vm_jit_error_count,vm_jit_map,count,row,observed);
        assert load64(record)==site;
        assert load64(record+8)==observed;
        assert load64(vm_jit_map+observed*8)==native_target;
    }
    return jit_relocate_selected_branch(start,end,count,op,arg,observed,row,site,native_target,failure,fuel,division,bounds,timeout);
}

requires size>=5 && size<=67108864;
requires branches>=1 && branches<=8191;
requires errors>=0 && errors<=24573;
requires count>=2 && count<=8192;
requires row>=0 && row<branches;
requires index>=1 && index<count;
requires writable_bytes(output,67108864);
requires writable_bytes(branch_table,8192*16);
requires writable_bytes(error_table,524288);
requires writable_bytes(map,8193*8);
requires disjoint_bytes(output,67108864,branch_table,8192*16);
requires disjoint_bytes(output,67108864,map,8193*8);
ensures writable_bytes(output,size);
ensures readable_bytes(branch_table,branches*16);
ensures readable_bytes(error_table,errors*16);
ensures readable_bytes(map,count*8);
ensures readable_bytes(branch_table+row*16,16);
ensures readable_bytes(map+index*8,8);
ensures disjoint_bytes(output,size,branch_table+row*16,16);
ensures disjoint_bytes(output,size,map+index*8,8);
lemma fn jit_relocation_scratch_spans(output,size,branch_table,branches,error_table,errors,map,count,row,index) {
    assert branches*16>=16 && branches*16<=8192*16;
    assert errors*16>=0 && errors*16<=524288;
    assert count*8>=16 && count*8<=8193*8;
    jit_branch_record_grant(branch_table,row);
    jit_map_word_before_tail(map,index);
    assert writable_bytes(output,size);
    assert disjoint_bytes(output,67108864,branch_table+row*16,16);
    jit_relocation_prefix_separate(output,size,branch_table+row*16,16);
    jit_map_scratch_separate(output,67108864,map,index);
    jit_relocation_prefix_separate(output,size,map+index*8,8);
}

requires base>=21 && base<=57365;
requires body>=base && body<=2154261;
requires size==body+110;
requires site>=base && site<=body-4;
requires target>=base && target<body;
ensures size>=5 && size<=67108864;
ensures site>=1 && site<=size-4;
ensures target>=0 && target<size;
lemma fn jit_exit_relocation_layout(base,body,size,site,target) {}

requires count>=2 && count<=8192;
requires branches>=0 && branches<=count-1;
requires errors>=0 && errors<=3*(count-1);
requires row>=0 && row<branches;
ensures branches>=1 && branches<=8191;
ensures errors<=24573;
ensures row<8192;
lemma fn jit_relocation_table_counts(count,row,branches,errors) {}

requires size>=5 && size<=67108864;
requires output>0 && output<=0x7fffffffffffffff-67108864;
ensures output<=0x7fffffffffffffff-size;
lemma fn jit_relocation_prefix_address(output,size) {}

requires size>=5 && size<=67108864;
requires writable_bytes(output,67108864);
requires readable_bytes(watched,len);
requires disjoint_bytes(output,67108864,watched,len);
ensures disjoint_bytes(output,size,watched,len);
lemma fn jit_relocation_prefix_separate(output,size,watched,len) {
    assert writable_bytes(output,size);
}

requires op>=10 && op<=12;
ensures op==10 || op==11 || op==12;
lemma fn jit_relocation_branch_opcode(op) {}

requires arg==pc;
requires pc>=start+16 && pc<end && pc%16==0;
ensures arg>=start+16 && arg<end && arg%16==0;
lemma fn jit_relocation_self_operand(arg,pc,start,end) {}
