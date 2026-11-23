// Observe an earlier error record across the production conditional jump append.
requires output_limit==67108864;
requires output_size>=0 && output_size<=output_limit-6;
requires writable_bytes(output,67108864);
requires vm_mode==0 && native_branch_mode==0;
requires vm_jit_error_count>=0 && vm_jit_error_count<32768;
requires writable_bytes(vm_jit_errors,524288);
requires op>=128 && op<=143;
requires disjoint_bytes(output,67108864,vm_jit_errors,524288);
requires earlier>=0 && earlier<vm_jit_error_count;
requires readable_bytes(vm_jit_errors+earlier*16,16);
requires disjoint_bytes(output,67108864,vm_jit_errors+earlier*16,16);
modifies output_size,native_address_site,native_boolean_end,vm_jit_error_count,bytes(vm_jit_errors+vm_jit_error_count*16,16),bytes(output,67108864);
ensures output_size==old(output_size)+6;
ensures result==old(output_size)+2;
ensures vm_jit_error_count==old(vm_jit_error_count)+1;
ensures load64(vm_jit_errors+old(vm_jit_error_count)*16)==result;
ensures load64(vm_jit_errors+old(vm_jit_error_count)*16+8)==kind;
ensures load64(vm_jit_errors+earlier*16)==old(load64(vm_jit_errors+earlier*16));
ensures load64(vm_jit_errors+earlier*16+8)==old(load64(vm_jit_errors+earlier*16+8));
fn jit_append_error_preserves_row(op,kind,earlier) {
    ghost let row=vm_jit_errors+earlier*16;
    ghost let displacement=load64(row);
    ghost let error_kind=load64(row+8);
    proof {
        jit_error_earlier_row(vm_jit_errors,earlier,vm_jit_error_count);
    }
    let at=vm_jit_error_jump(op,kind);
    proof {
        assert load64(row)==displacement;
        assert load64(row+8)==error_kind;
    }
    return at;
}

requires earlier>=0 && earlier<later && later<32768;
requires writable_bytes(table,524288);
ensures disjoint_bytes(table+later*16,16,table+earlier*16,16);
lemma fn jit_error_earlier_row(table,earlier,later) {
    assert earlier*16>=0 && earlier*16+16<=524288;
    assert later*16>=0 && later*16+16<=524288;
    assert writable_bytes(table+earlier*16,16);
    assert writable_bytes(table+later*16,16);
    assert (table+later*16)-(table+earlier*16)==(later-earlier)*16;
    assert later-earlier>=1 && later-earlier<=32767;
    jit_error_row_distance(later-earlier);
}

requires distance>=1 && distance<=32767;
ensures distance*16>=16;
lemma fn jit_error_row_distance(distance) {
    assert distance*16==distance<<4;
}
