// Single body-slot composition of the checked production emitter arms.
requires vm_mode==0 && native_branch_mode==0;
requires output_limit==67108864;
requires output_size>=0 && output_size<=output_limit-56;
requires vm_jit_error_count>=0 && vm_jit_error_count<=32766;
requires writable_bytes(output,67108864);
requires writable_bytes(vm_jit_errors,524288);
requires disjoint_bytes(output,67108864,vm_jit_errors,524288);
modifies output_size,native_address_site,native_address_kind,native_address_value,native_binary_cached,native_boolean_end,native_boolean_start,native_boolean_cc,vm_jit_error_count,bytes(vm_jit_errors,524288),bytes(output,67108864);
ensures output_size>=old(output_size)+4 && output_size<=old(output_size)+56;
ensures vm_jit_error_count==old(vm_jit_error_count)+2*(op==47 || op==37);
fn jit_emit_binary_with_guard(op) {
    ghost let entered=output_size;
PRODUCTION_OPTIONAL_DIVISION_GUARD
    ghost let prefix=output_size;
    let tail=jit_emit_binary_parts(op);
    proof {
        assert prefix==entered+39*(op==47 || op==37);
        assert output_size==prefix+tail;
        jit_guarded_binary_end(entered,prefix,tail,output_size);
    }
}

requires entered>=0 && entered<=67108864-56;
requires prefix==entered || prefix==entered+39;
requires tail>=4 && tail<=17;
requires cursor==prefix+tail;
ensures cursor>=entered+4;
ensures cursor<=entered+56;
lemma fn jit_guarded_binary_end(entered,prefix,tail,cursor) {
    if prefix==entered {
        assert prefix+4<=cursor;
        assert cursor<=prefix+17;
        assert entered+17<=entered+56;
        assert cursor>=entered+4;
        assert cursor<=entered+56;
    }else {
        assert prefix+4<=cursor;
        assert cursor<=prefix+17;
        assert prefix+4==entered+43;
        assert prefix+17==entered+56;
        assert entered+43>=entered+4;
        assert cursor>=entered+4;
        assert cursor<=entered+56;
    }
}

requires began>=0 && began<=67108864-139;
requires cursor==began+23;
requires next>=cursor && next<=cursor+116;
ensures next>=began+23;
ensures next<=began+139;
lemma fn jit_metered_body_end(began,cursor,next) {
    assert cursor+116==began+139;
}

requires began>=0 && began<=32765;
requires cursor==began+1;
requires next>=cursor && next<=cursor+2;
ensures next>=began+1;
ensures next<=began+3;
lemma fn jit_metered_error_end(began,cursor,next) {
    assert cursor+2==began+3;
}

requires output_limit==67108864;
requires vm_mode==0 && native_branch_mode==0;
requires !native_register_frame || !native_reg_replay;
requires vm_restricted!=0;
requires vm_heap_used>=16 && vm_heap_used<=1000000000;
requires vm_heap>0 && vm_heap<=0x7fffffffffffffff-vm_heap_used;
requires output_size>=0 && output_size<=output_limit-116;
requires vm_jit_error_count>=0 && vm_jit_error_count<=32766;
requires vm_jit_branch_count>=0 && vm_jit_branch_count<8192;
requires writable_bytes(output,67108864);
requires writable_bytes(vm_jit_errors,524288);
requires writable_bytes(vm_jit_branches,8192*16);
requires disjoint_bytes(output,67108864,vm_jit_errors,524288);
requires disjoint_bytes(output,67108864,vm_jit_branches,8192*16);
requires disjoint_bytes(vm_jit_errors,524288,vm_jit_branches,8192*16);
modifies vm_error,output_size,native_address_site,native_address_kind,native_address_value,native_binary_cached,native_boolean_end,native_boolean_start,native_boolean_cc,vm_jit_error_count,vm_jit_branch_count,bytes(vm_jit_errors,524288),bytes(vm_jit_branches+vm_jit_branch_count*16,16),bytes(output,67108864);
ensures output_size>=old(output_size);
ensures output_size<=old(output_size)+116;
ensures vm_jit_error_count>=old(vm_jit_error_count);
ensures vm_jit_error_count<=old(vm_jit_error_count)+2;
ensures vm_jit_branch_count>=old(vm_jit_branch_count);
ensures vm_jit_branch_count<=old(vm_jit_branch_count)+1;
ensures ((op==5 || op==6) && (arg<16 || arg>vm_heap_used-8)) || vm_error==old(vm_error);
ensures vm_jit_branch_count==old(vm_jit_branch_count)+(op>=10 && op<=12);
ensures op<10 || op>12 || load64(vm_jit_branches+old(vm_jit_branch_count)*16)==output_size-4;
ensures op<10 || op>12 || load64(vm_jit_branches+old(vm_jit_branch_count)*16+8)==(arg-start)/16;
fn jit_emit_body(op,arg,pc,start) {
    ghost let before=output_size;
    if op==1 || op==2 {
        jit_emit_simple_body(op,arg);
        proof {jit_body_extent_weaken(before,output_size,1,10);}
        return 0;
    }else if op==3 || op==4 {
        vm_jit_local(arg,op==4);
        proof {jit_body_extent_weaken(before,output_size,7,7);}
        return 0;
    }else if op==5 || op==6 || op==21 || op==22 {
        jit_emit_memory_body(op,arg);
        proof {jit_body_extent_weaken(before,output_size,13,30);}
        return 0;
    }else if op==7 {
        jit_emit_binary_with_guard(arg);
        proof {jit_body_extent_weaken(before,output_size,4,56);}
        return 0;
    }else if op==9 {
        epilogue();
        proof {jit_body_extent_weaken(before,output_size,2,2);}
        return 0;
    }else if op==10 || op==11 || op==12 {
        jit_emit_branch_body(op,arg,pc,start);
        return 0;
    }else if op==13 {
        ghost let width=9*(native_boolean_end!=output_size);
        normalize();
        proof {
            assert width==0 || width==9;
            jit_body_extent_weaken(before,output_size,width,width);
        }
        return 0;
    }else if op==14 || op==15 || op==16 {
        jit_emit_simple_body(op,arg);
        proof {jit_body_extent_weaken(before,output_size,1,10);}
    }
}

requires before>=0 && before<=67108864-116;
requires lower>=0 && lower<=upper && upper<=116;
requires after>=before+lower && after<=before+upper;
ensures after>=before;
ensures after<=before+116;
lemma fn jit_body_extent_weaken(before,after,lower,upper) {
    assert before+lower>=before;
    assert before+upper<=before+116;
}

requires output_limit==67108864;
requires vm_mode==0 && native_branch_mode==0;
requires !native_register_frame || !native_reg_replay;
requires vm_restricted!=0;
requires vm_heap_used>=16 && vm_heap_used<=1000000000;
requires vm_heap>0 && vm_heap<=0x7fffffffffffffff-vm_heap_used;
requires output_size>=0 && output_size<=output_limit-139;
requires vm_jit_error_count>=0 && vm_jit_error_count<=32765;
requires vm_jit_branch_count>=0 && vm_jit_branch_count<8192;
requires writable_bytes(output,67108864);
requires writable_bytes(vm_jit_errors,524288);
requires writable_bytes(vm_jit_branches,8192*16);
requires disjoint_bytes(output,67108864,vm_jit_errors,524288);
requires disjoint_bytes(output,67108864,vm_jit_branches,8192*16);
requires disjoint_bytes(vm_jit_errors,524288,vm_jit_branches,8192*16);
modifies vm_error,output_size,native_address_site,native_address_kind,native_address_value,native_binary_cached,native_boolean_end,native_boolean_start,native_boolean_cc,vm_jit_error_count,vm_jit_branch_count,bytes(vm_jit_errors,524288),bytes(vm_jit_branches+vm_jit_branch_count*16,16),bytes(output,67108864);
ensures output_size>=old(output_size)+23;
ensures output_size<=old(output_size)+139;
ensures vm_jit_error_count>=old(vm_jit_error_count)+1;
ensures vm_jit_error_count<=old(vm_jit_error_count)+3;
ensures vm_jit_branch_count>=old(vm_jit_branch_count);
ensures vm_jit_branch_count<=old(vm_jit_branch_count)+1;
ensures ((op==5 || op==6) && (arg<16 || arg>vm_heap_used-8)) || vm_error==old(vm_error);
fn jit_emit_all_metered(op,arg,pc,start) {
    ghost let began=output_size;
    ghost let first_error=vm_jit_error_count;
    vm_jit_meter();
    ghost let cursor=output_size;
    ghost let next_error=vm_jit_error_count;
    jit_emit_body(op,arg,pc,start);
    proof {
        jit_metered_body_end(began,cursor,output_size);
        jit_metered_error_end(first_error,next_error,vm_jit_error_count);
    }
}
