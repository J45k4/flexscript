// Preserve the instruction words through the production map, meter and dispatch.
// An admitted instruction also preserves the VM error state.
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
requires readable_bytes(bytecode+pc,8) && readable_bytes(bytecode+pc+8,8);
requires writable_bytes(output,67108864);
requires writable_bytes(vm_jit_errors,524288);
requires writable_bytes(vm_jit_branches,8192*16);
requires disjoint_bytes(output,67108864,vm_jit_errors,524288);
requires disjoint_bytes(output,67108864,vm_jit_branches,8192*16);
requires disjoint_bytes(vm_jit_errors,524288,vm_jit_branches,8192*16);
requires writable_bytes(vm_jit_map+slot*8,8);
requires disjoint_bytes(output,67108864,vm_jit_map+slot*8,8);
requires disjoint_bytes(vm_jit_errors,524288,vm_jit_map+slot*8,8);
requires disjoint_bytes(vm_jit_branches+vm_jit_branch_count*16,16,vm_jit_map+slot*8,8);
requires disjoint_bytes(output,67108864,bytecode+pc,16);
requires disjoint_bytes(vm_jit_errors,524288,bytecode+pc,16);
requires disjoint_bytes(vm_jit_branches+vm_jit_branch_count*16,16,bytecode+pc,16);
requires disjoint_bytes(vm_jit_map+slot*8,8,bytecode+pc,16);
modifies vm_error,output_size,native_address_site,native_address_kind,native_address_value,native_binary_cached,native_boolean_end,native_boolean_start,native_boolean_cc,vm_jit_error_count,vm_jit_branch_count,bytes(vm_jit_errors,524288),bytes(vm_jit_branches+vm_jit_branch_count*16,16),bytes(output,67108864),bytes(vm_jit_map+slot*8,8);
ensures output_size>=base && output_size<=base+256*((slot+1)-1);
ensures vm_jit_error_count>=0 && vm_jit_error_count<=3*((slot+1)-1);
ensures vm_jit_branch_count>=0 && vm_jit_branch_count<=(slot+1)-1;
ensures load64(vm_jit_map+slot*8)==old(output_size);
ensures load64(bytecode+pc)==old(load64(bytecode+pc));
ensures load64(bytecode+pc+8)==old(load64(bytecode+pc+8));
ensures !old(jit_leaf_opcode_admitted(load64(bytecode+pc),load64(bytecode+pc+8),start,end,slots,vm_heap_used)) || vm_error==old(vm_error);
ensures output_size>=old(output_size)+23;
ensures output_size>=old(output_size);
ensures vm_jit_branch_count>=old(vm_jit_branch_count);
ensures vm_jit_branch_count<=old(vm_jit_branch_count)+1;
ensures old(load64(bytecode+pc))<10 || old(load64(bytecode+pc))>12 || vm_jit_branch_count==old(vm_jit_branch_count)+1;
ensures old(load64(bytecode+pc))<10 || old(load64(bytecode+pc))>12 || load64(vm_jit_branches+old(vm_jit_branch_count)*16)==output_size-4;
ensures old(load64(bytecode+pc))<10 || old(load64(bytecode+pc))>12 || load64(vm_jit_branches+old(vm_jit_branch_count)*16+8)==(old(load64(bytecode+pc+8))-start)/16;
fn jit_emit_physical_slot(bytecode,pc,start,end,slots,slot,base) {
    ghost let cursor=output_size;
    ghost let errors=vm_jit_error_count;
    ghost let branches=vm_jit_branch_count;
    ghost let admitted_op=load64(bytecode+pc);
    ghost let admitted_arg=load64(bytecode+pc+8);
    proof {
        jit_headroom_at_slot(base,slot,cursor);
        jit_record_prefix_capacity(slot,errors,branches);
    }
PRODUCTION_SLOT_STORE_METER_LOAD
    proof {
        assert load64(vm_jit_map+slot*8)==cursor;
        assert op==admitted_op;
        assert arg==admitted_arg;
    }
    ghost let metered=output_size;
    ghost let metered_errors=vm_jit_error_count;
    jit_emit_body(op,arg,pc,start);
    proof {
        jit_metered_body_end(cursor,metered,output_size);
        jit_metered_error_end(errors,metered_errors,vm_jit_error_count);
        jit_headroom_next_slot(base,slot,cursor,output_size);
        jit_record_prefix_step(slot,errors,branches,vm_jit_error_count,vm_jit_branch_count);
    }
}

// Derive instruction separation from the actual backing region grants.
requires size>=16 && size<=268435456;
requires offset>=0 && offset<=size-16;
requires readable_bytes(code,size);
requires disjoint_bytes(arena,length,code,size);
requires length==67108864 || length==524288;
ensures disjoint_bytes(arena,length,code+offset,16);
lemma fn jit_staging_instruction_separate(arena,length,code,size,offset) {
    assert readable_bytes(code+offset,16);
}

requires size>=16 && size<=268435456;
requires pc>=0 && pc<=size-16;
requires slot>=1 && slot<=8191;
requires readable_bytes(code,size);
requires writable_bytes(map,8193*8);
requires disjoint_bytes(map,8193*8,code,size);
ensures writable_bytes(map+slot*8,8);
ensures disjoint_bytes(map+slot*8,8,code+pc,16);
lemma fn jit_map_instruction_separate(map,code,size,slot,pc) {
    assert slot*8>=8 && slot*8<=8191*8;
    assert readable_bytes(code+pc,16);
    assert writable_bytes(map+slot*8,8);
}

requires size>=16 && size<=268435456;
requires pc>=0 && pc<=size-16;
requires rows>=0 && rows<8192;
requires readable_bytes(code,size);
requires writable_bytes(branches,8192*16);
requires disjoint_bytes(branches,8192*16,code,size);
ensures disjoint_bytes(branches+rows*16,16,code+pc,16);
lemma fn jit_branch_instruction_separate(branches,code,size,rows,pc) {
    assert rows*16>=0 && rows*16<=8191*16;
    assert readable_bytes(code+pc,16);
    assert writable_bytes(branches+rows*16,16);
}

requires slot>=1 && slot<=8191;
requires writable_bytes(map,8193*8);
requires length==67108864 || length==524288 || length==8192*16;
requires disjoint_bytes(arena,length,map,8193*8);
ensures disjoint_bytes(arena,length,map+slot*8,8);
lemma fn jit_map_scratch_separate(arena,length,map,slot) {
    assert slot*8>=8 && slot*8<=8191*8;
    assert writable_bytes(map+slot*8,8);
}

requires slot>=1 && slot<=8191;
requires row>=0 && row<8192;
requires writable_bytes(map,8193*8);
requires writable_bytes(branches,8192*16);
requires disjoint_bytes(branches,8192*16,map,8193*8);
ensures disjoint_bytes(branches+row*16,16,map+slot*8,8);
lemma fn jit_branch_map_slots_separate(branches,row,map,slot) {
    assert slot*8>=8 && slot*8<=8191*8;
    assert row*16>=0 && row*16<=8191*16;
    assert writable_bytes(map+slot*8,8);
    assert writable_bytes(branches+row*16,16);
}

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
modifies vm_error,output_size,native_address_site,native_address_kind,native_address_value,native_binary_cached,native_boolean_end,native_boolean_start,native_boolean_cc,vm_jit_error_count,vm_jit_branch_count,bytes(vm_jit_errors,524288),bytes(vm_jit_branches+vm_jit_branch_count*16,16),bytes(output,67108864),bytes(vm_jit_map+slot*8,8);
ensures output_size>=base && output_size<=base+256*((slot+1)-1);
ensures vm_jit_error_count>=0 && vm_jit_error_count<=3*((slot+1)-1);
ensures vm_jit_branch_count>=0 && vm_jit_branch_count<=(slot+1)-1;
ensures load64(vm_jit_map+slot*8)==old(output_size);
ensures load64(bytecode+pc)==old(load64(bytecode+pc));
ensures load64(bytecode+pc+8)==old(load64(bytecode+pc+8));
ensures !old(jit_leaf_opcode_admitted(load64(bytecode+pc),load64(bytecode+pc+8),start,end,slots,vm_heap_used)) || vm_error==old(vm_error);
ensures output_size>=old(output_size)+23;
ensures output_size>=old(output_size);
ensures vm_jit_branch_count>=old(vm_jit_branch_count);
ensures vm_jit_branch_count<=old(vm_jit_branch_count)+1;
ensures old(load64(bytecode+pc))<10 || old(load64(bytecode+pc))>12 || vm_jit_branch_count==old(vm_jit_branch_count)+1;
ensures old(load64(bytecode+pc))<10 || old(load64(bytecode+pc))>12 || load64(vm_jit_branches+old(vm_jit_branch_count)*16)==output_size-4;
ensures old(load64(bytecode+pc))<10 || old(load64(bytecode+pc))>12 || load64(vm_jit_branches+old(vm_jit_branch_count)*16+8)==(old(load64(bytecode+pc+8))-start)/16;
fn jit_emit_physical_slot_from_scratch(bytecode,bytecode_size,pc,start,end,slots,slot,base) {
    ghost let branch_start=vm_jit_branch_count;
    proof {
        jit_granted_instruction_words(bytecode+pc);
        jit_staging_instruction_separate(output,67108864,bytecode,bytecode_size,pc);
        jit_staging_instruction_separate(vm_jit_errors,524288,bytecode,bytecode_size,pc);
        jit_map_instruction_separate(vm_jit_map,bytecode,bytecode_size,slot,pc);
        jit_branch_instruction_separate(vm_jit_branches,bytecode,bytecode_size,vm_jit_branch_count,pc);
        jit_map_scratch_separate(output,67108864,vm_jit_map,slot);
        jit_map_scratch_separate(vm_jit_errors,524288,vm_jit_map,slot);
        jit_branch_map_slots_separate(vm_jit_branches,vm_jit_branch_count,vm_jit_map,slot);
    }
    let emitted=jit_emit_physical_slot(bytecode,pc,start,end,slots,slot,base);
    proof {jit_branch_prefix_advance(slot,branch_start,vm_jit_branch_count);}
    return emitted;
}

PRODUCTION_INSTRUCTION_WORD_GRANT

requires slot>=1 && slot<8192;
requires before>=0 && before<=slot-1;
requires after>=before && after<=before+1;
ensures after>=0 && after<=(slot+1)-1;
lemma fn jit_branch_prefix_advance(slot,before,after) {
    assert (slot+1)-1==slot;
    assert before+1<=slot;
}
