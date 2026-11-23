// Counter projection of the x86-64 body emitter. Native byte emission,
// relocation-record stores and instruction reads are outside this projection.
global vm_jit_error_count=0;
global vm_jit_branch_count=0;

requires vm_jit_error_count>=0 && vm_jit_error_count<32768;
modifies vm_jit_error_count;
ensures vm_jit_error_count==old(vm_jit_error_count)+1;
fn jit_append_error_count() {
    vm_jit_error_count=vm_jit_error_count+1;
}

requires vm_jit_error_count>=0 && vm_jit_error_count<=32765;
modifies vm_jit_error_count;
ensures vm_jit_error_count==old(vm_jit_error_count)+1;
fn jit_meter_count() {
    jit_append_error_count();
}

requires vm_jit_error_count>=0 && vm_jit_error_count<=32766;
modifies vm_jit_error_count;
ensures vm_jit_error_count==old(vm_jit_error_count)+2;
fn jit_clock_count() {
    jit_append_error_count();
    jit_append_error_count();
}

requires vm_jit_error_count>=0 && vm_jit_error_count<=32766;
modifies vm_jit_error_count;
ensures vm_jit_error_count==old(vm_jit_error_count)+2;
fn jit_division_guard_count() {
    jit_append_error_count();
    jit_append_error_count();
}

requires vm_jit_error_count>=0 && vm_jit_error_count<=32765;
requires vm_jit_branch_count>=0 && vm_jit_branch_count<8192;
modifies vm_jit_error_count,vm_jit_branch_count;
ensures vm_jit_error_count>=old(vm_jit_error_count)+1;
ensures vm_jit_error_count<=old(vm_jit_error_count)+3;
ensures vm_jit_error_count==old(vm_jit_error_count)+1+
    (op==21 || op==22)+2*(op==7 && (arg==47 || arg==37))+
    2*((op==10 || op==11 || op==12) && arg<=pc);
ensures vm_jit_branch_count>=old(vm_jit_branch_count);
ensures vm_jit_branch_count<=old(vm_jit_branch_count)+1;
ensures vm_jit_branch_count==old(vm_jit_branch_count)+(op==10 || op==11 || op==12);
fn jit_body_record_counts(op,arg,pc) {
    jit_meter_count();
    if op==21 || op==22 {jit_append_error_count();}
    else if op==7 {if arg==47 || arg==37 {jit_division_guard_count();}}
    else if op==10 || op==11 || op==12 {
        if arg<=pc {jit_clock_count();}
        vm_jit_branch_count=vm_jit_branch_count+1;
    }
}

requires slot>=1 && slot<=8192;
requires errors>=0 && errors<=3*(slot-1);
requires branches>=0 && branches<=slot-1;
ensures errors<=24573 && branches<=8191;
ensures errors+3<=32768 && branches+1<=8192;
lemma fn jit_record_prefix_capacity(slot,errors,branches) {
    assert slot-1<=8191;
    assert 3*(slot-1)<=24573;
}

requires slot>=1 && slot<=8192;
requires errors>=0 && errors<=3*(slot-1);
requires branches>=0 && branches<=slot-1;
requires next_errors>=errors+1 && next_errors<=errors+3;
requires next_branches>=branches && next_branches<=branches+1;
ensures next_errors>=0 && next_errors<=3*((slot+1)-1);
ensures next_branches>=0 && next_branches<=(slot+1)-1;
lemma fn jit_record_prefix_step(slot,errors,branches,next_errors,next_branches) {
    assert (slot+1)-1==slot;
    assert 3*(slot-1)+3==3*slot;
}

requires slot>=1 && slot<=8192;
requires vm_jit_error_count>=0 && vm_jit_error_count<=3*(slot-1);
requires vm_jit_branch_count>=0 && vm_jit_branch_count<=slot-1;
modifies vm_jit_error_count,vm_jit_branch_count;
ensures vm_jit_error_count>=0 && vm_jit_error_count<=3*((slot+1)-1);
ensures vm_jit_branch_count>=0 && vm_jit_branch_count<=(slot+1)-1;
fn jit_count_body_slot(op,arg,pc,slot) {
    ghost let errors=vm_jit_error_count;
    ghost let branches=vm_jit_branch_count;
    proof {jit_record_prefix_capacity(slot,errors,branches);}
    jit_body_record_counts(op,arg,pc);
    proof {jit_record_prefix_step(slot,errors,branches,vm_jit_error_count,vm_jit_branch_count);}
}

requires count>=1 && count<=8192;
requires start>=0 && start<=67108864;
requires readable_bytes(code+start,count*16);
modifies vm_jit_error_count,vm_jit_branch_count;
ensures vm_jit_error_count>=0 && vm_jit_error_count<=3*(count-1);
ensures vm_jit_branch_count>=0 && vm_jit_branch_count<=count-1;
ensures vm_jit_error_count<=24573 && vm_jit_branch_count<=8191;
fn jit_record_counts_for_body(code,start,count) {
    vm_jit_branch_count=0;vm_jit_error_count=0;
    let map_slot=1;
    invariant map_slot>=1 && map_slot<=count;
    invariant vm_jit_error_count>=0 && vm_jit_error_count<=3*(map_slot-1);
    invariant vm_jit_branch_count>=0 && vm_jit_branch_count<=map_slot-1;
    decreases count-map_slot;
    while map_slot<count {
        let pc=start+map_slot*16;
        proof {jit_record_slot_reads(code+start,map_slot,count);}
        let op=load64(code+pc);let arg=load64(code+pc+8);
        jit_count_body_slot(op,arg,pc,map_slot);
        proof {assert map_slot+1<=count && count-(map_slot+1)>=0;}
        map_slot=map_slot+1;
    }
    proof {
        assert map_slot==count;
        jit_record_prefix_capacity(map_slot,vm_jit_error_count,vm_jit_branch_count);
        jit_record_prefix_finish(count,map_slot,vm_jit_error_count);
        assert vm_jit_error_count>=0 && vm_jit_error_count<=3*(count-1);
    }
}

requires count>=1 && count<=8192;
requires slot>=1 && slot<count;
requires readable_bytes(body,count*16);
ensures readable_bytes(body+slot*16,8);
ensures readable_bytes(body+slot*16+8,8);
lemma fn jit_record_slot_reads(body,slot,count) {
    assert slot*16>=16 && slot*16<=131056 && slot*16+16<=count*16;
}


requires count==slot;
requires errors>=0 && errors<=3*(slot-1);
ensures errors>=0 && errors<=3*(count-1);
lemma fn jit_record_prefix_finish(count,slot,errors) {
    assert slot-1==count-1;
}

requires writable_bytes(table,8192*64);
requires count>=0 && count<32768;
ensures writable_bytes(table+count*16,16);
lemma fn jit_error_record_grant(table,count) {
    assert count*16>=0 && count*16+16<=8192*64;
}

requires writable_bytes(table,8192*16);
requires count>=0 && count<8192;
ensures writable_bytes(table+count*16,16);
lemma fn jit_branch_record_grant(table,count) {
    assert count*16>=0 && count*16+16<=8192*16;
}
