// Effects of the production ordinary branch emitter after fuel metering.
// The projected result exposes the displacement position written to the table.
requires vm_mode==0 && native_branch_mode==0;
requires output_limit==67108864;
requires output_size>=0 && output_size<=output_limit-116;
requires op==10 || op==11 || op==12;
requires vm_jit_error_count>=0 && vm_jit_error_count<=32766;
requires vm_jit_branch_count>=0 && vm_jit_branch_count<8192;
requires writable_bytes(output,67108864);
requires writable_bytes(vm_jit_errors,524288);
requires writable_bytes(vm_jit_branches,8192*16);
requires disjoint_bytes(output,67108864,vm_jit_errors,524288);
requires disjoint_bytes(output,67108864,vm_jit_branches,8192*16);
requires disjoint_bytes(vm_jit_errors,524288,vm_jit_branches,8192*16);
modifies output_size,native_address_site,native_boolean_end,vm_jit_error_count,vm_jit_branch_count,bytes(vm_jit_errors,524288),bytes(vm_jit_branches+vm_jit_branch_count*16,16),bytes(output,67108864);
ensures op!=10 || arg<=pc || output_size==old(output_size)+5;
ensures op!=10 || arg>pc || output_size==old(output_size)+112;
ensures op==10 || arg<=pc || output_size==old(output_size)+9;
ensures op==10 || arg>pc || output_size==old(output_size)+116;
ensures output_size>=old(output_size)+5 && output_size<=old(output_size)+116;
ensures vm_jit_error_count==old(vm_jit_error_count)+2*(arg<=pc);
ensures vm_jit_branch_count==old(vm_jit_branch_count)+1;
ensures result==output_size-4;
ensures load64(vm_jit_branches+old(vm_jit_branch_count)*16)==result;
ensures load64(vm_jit_branches+old(vm_jit_branch_count)*16+8)==(arg-start)/16;
fn jit_emit_branch_body(op,arg,pc,start) {
    ghost let entered=output_size;
    ghost let row=vm_jit_branches+vm_jit_branch_count*16;
PRODUCTION_ORDINARY_BRANCH_BODY
    return -1;
}

requires output_limit==67108864;
requires output_size>=0 && output_size<=output_limit-139;
requires writable_bytes(output,67108864);
requires vm_mode==0 && native_branch_mode==0;
requires vm_jit_error_count>=0 && vm_jit_error_count<=32765;
requires writable_bytes(vm_jit_errors,524288);
requires op==10 || op==11 || op==12;
requires vm_jit_branch_count>=0 && vm_jit_branch_count<8192;
requires writable_bytes(vm_jit_branches,8192*16);
requires disjoint_bytes(output,67108864,vm_jit_branches,8192*16);
requires disjoint_bytes(vm_jit_errors,524288,vm_jit_branches,8192*16);
requires readable_bytes(observed,8);
requires disjoint_bytes(output,67108864,vm_jit_errors,524288);
requires disjoint_bytes(output,67108864,observed,8);
requires disjoint_bytes(vm_jit_errors,524288,observed,8);
requires disjoint_bytes(vm_jit_branches,8192*16,observed,8);
modifies output_size,native_address_site,native_boolean_end,vm_jit_error_count,vm_jit_branch_count,bytes(vm_jit_errors,524288),bytes(vm_jit_branches+vm_jit_branch_count*16,16),bytes(output,67108864);
ensures output_size>=old(output_size)+28 && output_size<=old(output_size)+139;
ensures vm_jit_error_count==old(vm_jit_error_count)+1+2*(arg<=pc);
ensures vm_jit_branch_count==old(vm_jit_branch_count)+1;
ensures result==output_size-4;
ensures load64(vm_jit_branches+old(vm_jit_branch_count)*16)==result;
ensures load64(vm_jit_branches+old(vm_jit_branch_count)*16+8)==(arg-start)/16;
ensures load64(observed)==old(load64(observed));
fn jit_emit_metered_branch_preserves_word(op,arg,pc,start,observed) {
    ghost let value=load64(observed);
    vm_jit_meter();
    proof {
        assert load64(observed)==value;
        jit_branch_append_separate(vm_jit_branches,vm_jit_branch_count,observed);
    }
    let at=jit_emit_branch_body(op,arg,pc,start);
    proof {assert load64(observed)==value;}
    return at;
}

requires count>=0 && count<8192;
requires writable_bytes(table,8192*16);
requires disjoint_bytes(table,8192*16,observed,8);
ensures disjoint_bytes(table+count*16,16,observed,8);
lemma fn jit_branch_append_separate(table,count,observed) {
    assert count*16>=0 && count*16+16<=8192*16;
}

requires output_limit==67108864;
requires output_size>=0 && output_size<=output_limit-139;
requires writable_bytes(output,67108864);
requires vm_mode==0 && native_branch_mode==0;
requires vm_jit_error_count>=0 && vm_jit_error_count<=32765;
requires writable_bytes(vm_jit_errors,524288);
requires op==10 || op==11 || op==12;
requires vm_jit_branch_count>=0 && vm_jit_branch_count<8192;
requires writable_bytes(vm_jit_branches,8192*16);
requires disjoint_bytes(output,67108864,vm_jit_branches,8192*16);
requires disjoint_bytes(vm_jit_errors,524288,vm_jit_branches,8192*16);
requires map_slot>=1 && map_slot<=8191;
requires watched>=1 && watched<=map_slot;
requires writable_bytes(vm_jit_map,8193*8);
requires writable_bytes(vm_jit_map+map_slot*8,8);
requires readable_bytes(vm_jit_map+watched*8,8);
requires disjoint_bytes(output,67108864,vm_jit_errors,524288);
requires disjoint_bytes(vm_jit_map,8193*8,output,67108864);
requires disjoint_bytes(vm_jit_map,8193*8,vm_jit_errors,524288);
requires disjoint_bytes(vm_jit_map,8193*8,vm_jit_branches,8192*16);
modifies output_size,native_address_site,native_boolean_end,vm_jit_error_count,vm_jit_branch_count,bytes(vm_jit_errors,524288),bytes(vm_jit_branches+vm_jit_branch_count*16,16),bytes(output,67108864),bytes(vm_jit_map+map_slot*8,8);
ensures output_size>=old(output_size)+28 && output_size<=old(output_size)+139;
ensures vm_jit_error_count==old(vm_jit_error_count)+1+2*(arg<=pc);
ensures vm_jit_branch_count==old(vm_jit_branch_count)+1;
ensures result==output_size-4;
ensures load64(vm_jit_branches+old(vm_jit_branch_count)*16)==result;
ensures load64(vm_jit_branches+old(vm_jit_branch_count)*16+8)==(arg-start)/16;
ensures watched!=map_slot || load64(vm_jit_map+watched*8)==old(output_size);
ensures watched==map_slot || load64(vm_jit_map+watched*8)==old(load64(vm_jit_map+watched*8));
fn jit_record_map_and_emit_branch(op,arg,pc,start,map_slot,watched) {
    ghost let before=output_size;
    let word=vm_jit_map+watched*8;
    ghost let previous=load64(word);
    proof {
        jit_emit_map_observer(vm_jit_map,watched,output,vm_jit_errors);
        jit_branch_map_observer(vm_jit_map,watched,vm_jit_branches);
        if watched==map_slot {jit_record_map_alias(vm_jit_map,map_slot,watched);}
        else {jit_record_map_ordered_words(vm_jit_map,watched,map_slot);}
    }
PRODUCTION_MAP_STORE
    ghost let stored=load64(word);
    proof {
        assert watched!=map_slot || stored==before;
        assert watched==map_slot || stored==previous;
    }
    let at=jit_emit_metered_branch_preserves_word(op,arg,pc,start,word);
    proof {assert load64(word)==stored;}
    return at;
}


requires watched>=1 && watched<=8191;
requires writable_bytes(map,8193*8);
requires disjoint_bytes(map,8193*8,branches,8192*16);
ensures disjoint_bytes(branches,8192*16,map+watched*8,8);
lemma fn jit_branch_map_observer(map,watched,branches) {
    assert watched*8>=8 && watched*8<=8191*8;
}

requires output_limit==67108864;
requires output_size>=0 && output_size<=output_limit-139;
requires writable_bytes(output,67108864);
requires vm_mode==0 && native_branch_mode==0;
requires vm_jit_error_count>=0 && vm_jit_error_count<=32765;
requires writable_bytes(vm_jit_errors,524288);
requires op==10 || op==11 || op==12;
requires vm_jit_branch_count>=0 && vm_jit_branch_count<8192;
requires writable_bytes(vm_jit_branches,8192*16);
requires disjoint_bytes(output,67108864,vm_jit_branches,8192*16);
requires disjoint_bytes(vm_jit_errors,524288,vm_jit_branches,8192*16);
requires map_slot>=1 && map_slot<=8191;
requires watched>=1 && watched<=map_slot;
requires writable_bytes(vm_jit_map,8193*8);
requires writable_bytes(vm_jit_map+map_slot*8,8);
requires readable_bytes(vm_jit_map+watched*8,8);
requires disjoint_bytes(output,67108864,vm_jit_errors,524288);
requires disjoint_bytes(vm_jit_map,8193*8,output,67108864);
requires disjoint_bytes(vm_jit_map,8193*8,vm_jit_errors,524288);
requires disjoint_bytes(vm_jit_map,8193*8,vm_jit_branches,8192*16);
requires earlier>=0 && earlier<vm_jit_branch_count;
requires readable_bytes(vm_jit_branches+earlier*16,16);
modifies output_size,native_address_site,native_boolean_end,vm_jit_error_count,vm_jit_branch_count,bytes(vm_jit_errors,524288),bytes(vm_jit_branches+vm_jit_branch_count*16,16),bytes(output,67108864),bytes(vm_jit_map+map_slot*8,8);
ensures output_size>=old(output_size)+28 && output_size<=old(output_size)+139;
ensures vm_jit_error_count==old(vm_jit_error_count)+1+2*(arg<=pc);
ensures vm_jit_branch_count==old(vm_jit_branch_count)+1;
ensures result==output_size-4;
ensures load64(vm_jit_branches+old(vm_jit_branch_count)*16)==result;
ensures load64(vm_jit_branches+old(vm_jit_branch_count)*16+8)==(arg-start)/16;
ensures watched!=map_slot || load64(vm_jit_map+watched*8)==old(output_size);
ensures watched==map_slot || load64(vm_jit_map+watched*8)==old(load64(vm_jit_map+watched*8));
ensures load64(vm_jit_branches+earlier*16)==old(load64(vm_jit_branches+earlier*16));
ensures load64(vm_jit_branches+earlier*16+8)==old(load64(vm_jit_branches+earlier*16+8));
fn jit_record_map_and_preserve_branch(op,arg,pc,start,map_slot,watched,earlier) {
    ghost let row=vm_jit_branches+earlier*16;
    ghost let site=load64(row);
    ghost let target=load64(row+8);
    proof {
        jit_branch_earlier_row(vm_jit_branches,earlier,vm_jit_branch_count);
        jit_branch_row_external_spans(vm_jit_branches,earlier,output,vm_jit_errors);
        jit_branch_map_row_disjoint(vm_jit_map,map_slot,vm_jit_branches,earlier);
    }
    let at=jit_record_map_and_emit_branch(op,arg,pc,start,map_slot,watched);
    proof {
        assert load64(row)==site;
        assert load64(row+8)==target;
    }
    return at;
}

requires map_slot>=1 && map_slot<=8191;
requires earlier>=0 && earlier<8192;
requires writable_bytes(map,8193*8);
requires writable_bytes(table,8192*16);
requires disjoint_bytes(map,8193*8,table,8192*16);
ensures disjoint_bytes(map+map_slot*8,8,table+earlier*16,16);
lemma fn jit_branch_map_row_disjoint(map,map_slot,table,earlier) {
    assert map_slot*8>=8 && map_slot*8<=8191*8;
    assert earlier*16>=0 && earlier*16+16<=8192*16;
}

requires earlier>=0 && earlier<later && later<8192;
requires writable_bytes(table,8192*16);
ensures disjoint_bytes(table+later*16,16,table+earlier*16,16);
lemma fn jit_branch_earlier_row(table,earlier,later) {
    assert earlier*16>=0 && earlier*16+16<=8192*16;
    assert later*16>=0 && later*16+16<=8192*16;
    assert writable_bytes(table+earlier*16,16);
    assert writable_bytes(table+later*16,16);
    assert (table+later*16)-(table+earlier*16)==(later-earlier)*16;
    assert later-earlier>=1 && later-earlier<=8191;
    jit_branch_distance_nonzero(later-earlier);
}

requires earlier>=0 && earlier<8192;
requires writable_bytes(table,8192*16);
requires disjoint_bytes(output_base,67108864,table,8192*16);
requires disjoint_bytes(errors,524288,table,8192*16);
ensures disjoint_bytes(output_base,67108864,table+earlier*16,16);
ensures disjoint_bytes(errors,524288,table+earlier*16,16);
lemma fn jit_branch_row_external_spans(table,earlier,output_base,errors) {
    assert earlier*16>=0 && earlier*16+16<=8192*16;
}

requires distance>=1 && distance<=8191;
ensures distance*16>=16;
lemma fn jit_branch_distance_nonzero(distance) {
    assert distance*16==distance<<4;
}
