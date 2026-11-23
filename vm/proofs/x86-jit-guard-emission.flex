// Native conditional jump, error record, and guard immediate emission.

fn emit(b) {
    native_address_site=-1;
    native_boolean_end=-1;
    if output_size >= output_limit {return -1;}
    store8(output + output_size, b);
    output_size = output_size + 1;
    return 0;
}
requires output_limit==67108864;
requires output_size>=0 && output_size<=output_limit-4;
requires writable_bytes(output+output_size,4);
requires value==0;
modifies output_size,native_address_site,native_boolean_end,bytes(output+output_size,4);
ensures output_size==old(output_size)+4;
ensures load8(output+old(output_size)+0)==0;
ensures load8(output+old(output_size)+1)==0;
ensures load8(output+old(output_size)+2)==0;
ensures load8(output+old(output_size)+3)==0;
fn emit32(value) {
    let i = 0;
    ghost let entered=output_size;
    invariant i>=0 && i<=4;
    invariant output_size==entered+i;
    invariant i<1 || load8(output+entered+0)==0;
    invariant i<2 || load8(output+entered+1)==0;
    invariant i<3 || load8(output+entered+2)==0;
    invariant i<4 || load8(output+entered+3)==0;
    decreases 4-i;
    while i < 4 {
        proof {assert output_size<output_limit;}
        emit(value >> (i * 8));
        i = i + 1;
    }
    return 0;
}
requires output_limit==67108864;
requires output_size>=0 && output_size<=output_limit-6;
requires writable_bytes(output+output_size,6);
requires vm_mode==0 && native_branch_mode==0;
requires opcode==132 || opcode==133;
modifies output_size,native_address_site,native_boolean_end,bytes(output+output_size,6);
ensures output_size==old(output_size)+6;
ensures result==old(output_size)+2;
ensures load8(output+old(output_size))==15;
ensures load8(output+old(output_size)+1)==opcode;
ensures load8(output+result+0)==0;
ensures load8(output+result+1)==0;
ensures load8(output+result+2)==0;
ensures load8(output+result+3)==0;
fn jump(opcode) {
    if vm_mode {return -1;}
    if native_branch_mode {return -1;}
    ghost let started=output_size;
    proof {
        x86_near_branch_tail(output+started);
        assert output_size<output_limit;
    }
    if opcode != 233 { emit(15); }
    proof {assert output_size==started+1;assert output_size<output_limit;}
    emit(opcode);
    let at = output_size;
    proof {
        assert at==started+2;
        assert output_size<=output_limit-4;
        x86_shift_branch_address(output,started,at);
        x86_near_branch_alias(output+started+2,output+at,output+started);
    }
    emit32(0);
    return at;
}
requires output_limit==67108864;
requires output_size>=0 && output_size<=output_limit-6;
requires writable_bytes(output+output_size,6);
requires vm_mode==0 && native_branch_mode==0;
requires op==132 && kind==2;
requires vm_jit_error_count>=0 && vm_jit_error_count<32768;
requires writable_bytes(vm_jit_errors+vm_jit_error_count*16,16);
requires disjoint_bytes(output+output_size,6,vm_jit_errors+vm_jit_error_count*16,16);
modifies vm_jit_error_count,output_size,native_address_site,native_boolean_end,bytes(output+output_size,6),bytes(vm_jit_errors+vm_jit_error_count*16,16);
ensures output_size==old(output_size)+6;
ensures result==old(output_size)+2;
ensures vm_jit_error_count==old(vm_jit_error_count)+1;
ensures load64(vm_jit_errors+old(vm_jit_error_count)*16)==result;
ensures load64(vm_jit_errors+old(vm_jit_error_count)*16+8)==kind;
ensures load8(output+old(output_size)+0)==15;
ensures load8(output+old(output_size)+1)==132;
ensures load8(output+result+0)==0;
ensures load8(output+result+1)==0;
ensures load8(output+result+2)==0;
ensures load8(output+result+3)==0;
fn vm_jit_error_jump(op,kind) {
    let at=jump(op);let record=vm_jit_errors+vm_jit_error_count*16;
    store64(record,at);store64(record+8,kind);vm_jit_error_count=vm_jit_error_count+1;return at;
}

requires writable_bytes(base,6);
ensures writable_bytes(base+2,4);
ensures disjoint_bytes(base+2,4,base,2);
lemma fn x86_near_branch_tail(base) {}

requires tail==start+2;
ensures base+tail==base+start+2;
lemma fn x86_shift_branch_address(base,start,tail) {
    x86_branch_add_alias(base,tail,start+2);
}

requires left==right;
ensures base+left==base+right;
lemma fn x86_branch_add_alias(base,left,right) {}

requires source==alias;
requires writable_bytes(source,4);
requires disjoint_bytes(source,4,head,2);
ensures writable_bytes(alias,4);
ensures disjoint_bytes(alias,4,head,2);
lemma fn x86_near_branch_alias(source,alias,head) {}

requires output_limit==67108864;
requires output_size>=0 && output_size<=output_limit-8;
requires writable_bytes(output+output_size,8);
requires value==0x8000000000000000;
modifies output_size,native_address_site,native_boolean_end,bytes(output+output_size,8);
ensures output_size==old(output_size)+8;
ensures load8(output+old(output_size)+0)==0;
ensures load8(output+old(output_size)+1)==0;
ensures load8(output+old(output_size)+2)==0;
ensures load8(output+old(output_size)+3)==0;
ensures load8(output+old(output_size)+4)==0;
ensures load8(output+old(output_size)+5)==0;
ensures load8(output+old(output_size)+6)==0;
ensures load8(output+old(output_size)+7)==128;
fn emit64(value) {
    let i = 0;
    ghost let entered=output_size;
    invariant i>=0 && i<=8;
    invariant output_size==entered+i;
    invariant i<1 || load8(output+entered+0)==0;
    invariant i<2 || load8(output+entered+1)==0;
    invariant i<3 || load8(output+entered+2)==0;
    invariant i<4 || load8(output+entered+3)==0;
    invariant i<5 || load8(output+entered+4)==0;
    invariant i<6 || load8(output+entered+5)==0;
    invariant i<7 || load8(output+entered+6)==0;
    invariant i<8 || load8(output+entered+7)==128;
    decreases 8-i;
    while i < 8 {
        proof {assert output_size<output_limit;}
        emit(value >> (i * 8));
        i = i + 1;
    }
    return 0;
}
