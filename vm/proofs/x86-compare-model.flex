import "x86-subtract-model.flex";

fn x86_test_condition(cc,flags) {
    let zero=(flags&0x40)!=0;
    let less=((flags>>7)^(flags>>11))&1;
    if cc==148 {return zero;}
    if cc==149 {return !zero;}
    if cc==156 {return less;}
    if cc==157 {return !less;}
    if cc==158 {return zero || less;}
    if cc==159 {return !zero && !less;}
    return 0;
}

spec fn x86_compare_signed_less(left,right) {
    let difference=left-right;
    return (difference<0)^(((left^right)&(left^difference))<0);
}
ensures ((left-right)==0)==(left==right);
ensures ((left-right)!=0)==(left!=right);
ensures x86_compare_signed_less(left,right)==(left<right);
ensures !x86_compare_signed_less(left,right)==(left>=right);
ensures (((left-right)==0)||x86_compare_signed_less(left,right))==(left<=right);
ensures (((left-right)!=0)&&!x86_compare_signed_less(left,right))==(left>right);
lemma fn x86_compare_conditions(left,right) {}

// The proof checks each instruction encoding at the current RIP before
// applying the decoded transition. POP reads its operand from the live stack.
fn x86_model_pop_decoded(word) {
    x86_model_rcx=word;
    x86_model_rsp=x86_model_rsp+8;
    x86_model_rip=x86_model_rip+1;
}
fn x86_model_compare_decoded() {
    let pc=x86_model_rip;
    let difference=x86_model_rcx-x86_model_rax;
    x86_model_rflags=(x86_model_rflags&(~0x8d5))|x86_model_sub_flags(x86_model_rcx,x86_model_rax,difference);
    x86_model_rip=pc+3;
}
fn x86_model_set_decoded(cc) {
    let pc=x86_model_rip;
    x86_model_rax=(x86_model_rax&(~255))|x86_test_condition(cc,x86_model_rflags);
    x86_model_rip=pc+3;
}
fn x86_model_extend_decoded() {
    let pc=x86_model_rip;
    x86_model_rax=x86_model_rax&255;
    x86_model_rip=pc+3;
}

// The three separation predicates cover the entire ten-byte emitted sequence.
requires native_binary_cached==0;
requires output_limit==67108864 || output_limit==268435456;
requires output_size>=0 && output_size<=output_limit-10;
requires output+output_size<=9223372036854775797;
requires x86_model_rsp>=0 && x86_model_rsp<=9223372036854775799;
requires writable_bytes(output+output_size,10);
requires readable_bytes(x86_model_rsp,8);
requires disjoint_bytes(output+output_size,4,x86_model_rsp,8);
requires disjoint_bytes(output+output_size+4,4,x86_model_rsp,8);
requires disjoint_bytes(output+output_size+8,2,x86_model_rsp,8);
reads native_binary_cached,output,output_size,output_limit,native_address_site,native_boolean_end,native_register_frame,frontend_language,native_boolean_start,native_boolean_cc,
    x86_model_rip,x86_model_rsp,x86_model_rcx,x86_model_rax,x86_model_rflags,bytes(output+output_size,10),bytes(x86_model_rsp,8);
modifies output_size,native_address_site,native_boolean_end,native_boolean_start,native_boolean_cc,
    x86_model_rip,x86_model_rsp,x86_model_rcx,x86_model_rax,x86_model_rflags,bytes(output+output_size,10);
ensures result==1 && x86_model_rip==old(output+output_size)+10 && x86_model_rsp==old(x86_model_rsp)+8;
ensures x86_model_rcx==old(load64(x86_model_rsp));
ensures x86_model_rax==(x86_model_rcx == old(x86_model_rax));
ensures (x86_model_rflags&(~0x8d5))==(old(x86_model_rflags)&(~0x8d5));
fn x86_emit_and_model_eq() {
    x86_model_rip=output+output_size;
    let top=load64(x86_model_rsp);
    let right=x86_model_rax;
    proof {
        assert output_size < output_limit;
        assert output_size+1 < output_limit;
        assert output_size+2 < output_limit;
        assert output_size+3 < output_limit;
        assert output_size+4 < output_limit;
        assert output_size+5 < output_limit;
        assert output_size+6 < output_limit;
        assert output_size+7 < output_limit;
        assert output_size+8 < output_limit;
        assert output_size+9 < output_limit;
    }
    native_binary(259);
    proof {
        assert load8(x86_model_rip)==0x59;
    }
    let word=load64(x86_model_rsp);
    assert word==top;
    let vm_result=vm_binary(259,word,x86_model_rax);
    x86_model_pop_decoded(word);
    assert x86_model_rcx==top;
    assert x86_model_rax==right;
    proof {
        assert load8(x86_model_rip)==0x48;
        assert load8(x86_model_rip+1)==0x39;
        assert load8(x86_model_rip+2)==0xc1;
    }
    x86_model_compare_decoded();
    let flags=x86_model_sub_flags(word,right,word-right);
    assert (x86_model_rflags&0x8d5)==flags;
    let condition=x86_test_condition(148,flags);
    proof {x86_compare_conditions(word,right);}
    assert condition==vm_result;
    proof {
        assert load8(x86_model_rip)==0x0f;
        assert load8(x86_model_rip+2)==0xc0;
    }
    let condition_code=load8(x86_model_rip+1);
    assert condition_code==148;
    x86_model_set_decoded(condition_code);
    assert (x86_model_rax&255)==condition;
    proof {
        assert load8(x86_model_rip)==0x0f;
        assert load8(x86_model_rip+1)==0xb6;
        assert load8(x86_model_rip+2)==0xc0;
    }
    x86_model_extend_decoded();
    assert x86_model_rax==vm_result;
    return 1;
}

requires native_binary_cached==0;
requires output_limit==67108864 || output_limit==268435456;
requires output_size>=0 && output_size<=output_limit-10;
requires output+output_size<=9223372036854775797;
requires x86_model_rsp>=0 && x86_model_rsp<=9223372036854775799;
requires writable_bytes(output+output_size,10);
requires readable_bytes(x86_model_rsp,8);
requires disjoint_bytes(output+output_size,4,x86_model_rsp,8);
requires disjoint_bytes(output+output_size+4,4,x86_model_rsp,8);
requires disjoint_bytes(output+output_size+8,2,x86_model_rsp,8);
reads native_binary_cached,output,output_size,output_limit,native_address_site,native_boolean_end,native_register_frame,frontend_language,native_boolean_start,native_boolean_cc,
    x86_model_rip,x86_model_rsp,x86_model_rcx,x86_model_rax,x86_model_rflags,bytes(output+output_size,10),bytes(x86_model_rsp,8);
modifies output_size,native_address_site,native_boolean_end,native_boolean_start,native_boolean_cc,
    x86_model_rip,x86_model_rsp,x86_model_rcx,x86_model_rax,x86_model_rflags,bytes(output+output_size,10);
ensures result==1 && x86_model_rip==old(output+output_size)+10 && x86_model_rsp==old(x86_model_rsp)+8;
ensures x86_model_rcx==old(load64(x86_model_rsp));
ensures x86_model_rax==(x86_model_rcx != old(x86_model_rax));
ensures (x86_model_rflags&(~0x8d5))==(old(x86_model_rflags)&(~0x8d5));
fn x86_emit_and_model_ne() {
    x86_model_rip=output+output_size;
    let top=load64(x86_model_rsp);
    let right=x86_model_rax;
    proof {
        assert output_size < output_limit;
        assert output_size+1 < output_limit;
        assert output_size+2 < output_limit;
        assert output_size+3 < output_limit;
        assert output_size+4 < output_limit;
        assert output_size+5 < output_limit;
        assert output_size+6 < output_limit;
        assert output_size+7 < output_limit;
        assert output_size+8 < output_limit;
        assert output_size+9 < output_limit;
    }
    native_binary(260);
    proof {
        assert load8(x86_model_rip)==0x59;
    }
    let word=load64(x86_model_rsp);
    assert word==top;
    let vm_result=vm_binary(260,word,x86_model_rax);
    x86_model_pop_decoded(word);
    assert x86_model_rcx==top;
    assert x86_model_rax==right;
    proof {
        assert load8(x86_model_rip)==0x48;
        assert load8(x86_model_rip+1)==0x39;
        assert load8(x86_model_rip+2)==0xc1;
    }
    x86_model_compare_decoded();
    let flags=x86_model_sub_flags(word,right,word-right);
    assert (x86_model_rflags&0x8d5)==flags;
    let condition=x86_test_condition(149,flags);
    proof {x86_compare_conditions(word,right);}
    assert condition==vm_result;
    proof {
        assert load8(x86_model_rip)==0x0f;
        assert load8(x86_model_rip+2)==0xc0;
    }
    let condition_code=load8(x86_model_rip+1);
    assert condition_code==149;
    x86_model_set_decoded(condition_code);
    assert (x86_model_rax&255)==condition;
    proof {
        assert load8(x86_model_rip)==0x0f;
        assert load8(x86_model_rip+1)==0xb6;
        assert load8(x86_model_rip+2)==0xc0;
    }
    x86_model_extend_decoded();
    assert x86_model_rax==vm_result;
    return 1;
}

// Signed less-than uses the sign and overflow flags.
requires native_binary_cached==0;
requires output_limit==67108864 || output_limit==268435456;
requires output_size>=0 && output_size<=output_limit-10;
requires output+output_size<=9223372036854775797;
requires x86_model_rsp>=0 && x86_model_rsp<=9223372036854775799;
requires writable_bytes(output+output_size,10);
requires readable_bytes(x86_model_rsp,8);
requires disjoint_bytes(output+output_size,4,x86_model_rsp,8);
requires disjoint_bytes(output+output_size+4,4,x86_model_rsp,8);
requires disjoint_bytes(output+output_size+8,2,x86_model_rsp,8);
reads native_binary_cached,output,output_size,output_limit,native_address_site,native_boolean_end,native_register_frame,frontend_language,native_boolean_start,native_boolean_cc,
    x86_model_rip,x86_model_rsp,x86_model_rcx,x86_model_rax,x86_model_rflags,bytes(output+output_size,10),bytes(x86_model_rsp,8);
modifies output_size,native_address_site,native_boolean_end,native_boolean_start,native_boolean_cc,
    x86_model_rip,x86_model_rsp,x86_model_rcx,x86_model_rax,x86_model_rflags,bytes(output+output_size,10);
ensures result==1 && x86_model_rip==old(output+output_size)+10 && x86_model_rsp==old(x86_model_rsp)+8;
ensures x86_model_rcx==old(load64(x86_model_rsp));
ensures x86_model_rax==(x86_model_rcx < old(x86_model_rax));
ensures (x86_model_rflags&(~0x8d5))==(old(x86_model_rflags)&(~0x8d5));
fn x86_emit_and_model_lt() {
    x86_model_rip=output+output_size;
    let top=load64(x86_model_rsp);
    let right=x86_model_rax;
    proof {
        assert output_size < output_limit;
        assert output_size+1 < output_limit;
        assert output_size+2 < output_limit;
        assert output_size+3 < output_limit;
        assert output_size+4 < output_limit;
        assert output_size+5 < output_limit;
        assert output_size+6 < output_limit;
        assert output_size+7 < output_limit;
        assert output_size+8 < output_limit;
        assert output_size+9 < output_limit;
    }
    native_binary(60);
    proof {
        assert load8(x86_model_rip)==0x59;
    }
    let word=load64(x86_model_rsp);
    assert word==top;
    let vm_result=vm_binary(60,word,x86_model_rax);
    x86_model_pop_decoded(word);
    assert x86_model_rcx==top;
    assert x86_model_rax==right;
    proof {
        assert load8(x86_model_rip)==0x48;
        assert load8(x86_model_rip+1)==0x39;
        assert load8(x86_model_rip+2)==0xc1;
    }
    x86_model_compare_decoded();
    let flags=x86_model_sub_flags(word,right,word-right);
    assert (x86_model_rflags&0x8d5)==flags;
    let condition=x86_test_condition(156,flags);
    proof {x86_compare_conditions(word,right);}
    assert condition==vm_result;
    proof {
        assert load8(x86_model_rip)==0x0f;
        assert load8(x86_model_rip+2)==0xc0;
    }
    let condition_code=load8(x86_model_rip+1);
    assert condition_code==156;
    x86_model_set_decoded(condition_code);
    assert (x86_model_rax&255)==condition;
    proof {
        assert load8(x86_model_rip)==0x0f;
        assert load8(x86_model_rip+1)==0xb6;
        assert load8(x86_model_rip+2)==0xc0;
    }
    x86_model_extend_decoded();
    assert x86_model_rax==vm_result;
    return 1;
}

// Signed greater-than-or-equal complements signed less-than.
requires native_binary_cached==0;
requires output_limit==67108864 || output_limit==268435456;
requires output_size>=0 && output_size<=output_limit-10;
requires output+output_size<=9223372036854775797;
requires x86_model_rsp>=0 && x86_model_rsp<=9223372036854775799;
requires writable_bytes(output+output_size,10);
requires readable_bytes(x86_model_rsp,8);
requires disjoint_bytes(output+output_size,4,x86_model_rsp,8);
requires disjoint_bytes(output+output_size+4,4,x86_model_rsp,8);
requires disjoint_bytes(output+output_size+8,2,x86_model_rsp,8);
reads native_binary_cached,output,output_size,output_limit,native_address_site,native_boolean_end,native_register_frame,frontend_language,native_boolean_start,native_boolean_cc,
    x86_model_rip,x86_model_rsp,x86_model_rcx,x86_model_rax,x86_model_rflags,bytes(output+output_size,10),bytes(x86_model_rsp,8);
modifies output_size,native_address_site,native_boolean_end,native_boolean_start,native_boolean_cc,
    x86_model_rip,x86_model_rsp,x86_model_rcx,x86_model_rax,x86_model_rflags,bytes(output+output_size,10);
ensures result==1 && x86_model_rip==old(output+output_size)+10 && x86_model_rsp==old(x86_model_rsp)+8;
ensures x86_model_rcx==old(load64(x86_model_rsp));
ensures x86_model_rax==(x86_model_rcx >= old(x86_model_rax));
ensures (x86_model_rflags&(~0x8d5))==(old(x86_model_rflags)&(~0x8d5));
fn x86_emit_and_model_ge() {
    x86_model_rip=output+output_size;
    let top=load64(x86_model_rsp);
    let right=x86_model_rax;
    proof {
        assert output_size < output_limit;
        assert output_size+1 < output_limit;
        assert output_size+2 < output_limit;
        assert output_size+3 < output_limit;
        assert output_size+4 < output_limit;
        assert output_size+5 < output_limit;
        assert output_size+6 < output_limit;
        assert output_size+7 < output_limit;
        assert output_size+8 < output_limit;
        assert output_size+9 < output_limit;
    }
    native_binary(262);
    proof {
        assert load8(x86_model_rip)==0x59;
    }
    let word=load64(x86_model_rsp);
    assert word==top;
    let vm_result=vm_binary(262,word,x86_model_rax);
    x86_model_pop_decoded(word);
    assert x86_model_rcx==top;
    assert x86_model_rax==right;
    proof {
        assert load8(x86_model_rip)==0x48;
        assert load8(x86_model_rip+1)==0x39;
        assert load8(x86_model_rip+2)==0xc1;
    }
    x86_model_compare_decoded();
    let flags=x86_model_sub_flags(word,right,word-right);
    assert (x86_model_rflags&0x8d5)==flags;
    let condition=x86_test_condition(157,flags);
    proof {x86_compare_conditions(word,right);}
    assert condition==vm_result;
    proof {
        assert load8(x86_model_rip)==0x0f;
        assert load8(x86_model_rip+2)==0xc0;
    }
    let condition_code=load8(x86_model_rip+1);
    assert condition_code==157;
    x86_model_set_decoded(condition_code);
    assert (x86_model_rax&255)==condition;
    proof {
        assert load8(x86_model_rip)==0x0f;
        assert load8(x86_model_rip+1)==0xb6;
        assert load8(x86_model_rip+2)==0xc0;
    }
    x86_model_extend_decoded();
    assert x86_model_rax==vm_result;
    return 1;
}

requires native_binary_cached==0;
requires output_limit==67108864 || output_limit==268435456;
requires output_size>=0 && output_size<=output_limit-10;
requires output+output_size<=9223372036854775797;
requires x86_model_rsp>=0 && x86_model_rsp<=9223372036854775799;
requires writable_bytes(output+output_size,10);
requires readable_bytes(x86_model_rsp,8);
requires disjoint_bytes(output+output_size,4,x86_model_rsp,8);
requires disjoint_bytes(output+output_size+4,4,x86_model_rsp,8);
requires disjoint_bytes(output+output_size+8,2,x86_model_rsp,8);
reads native_binary_cached,output,output_size,output_limit,native_address_site,native_boolean_end,native_register_frame,frontend_language,native_boolean_start,native_boolean_cc,
    x86_model_rip,x86_model_rsp,x86_model_rcx,x86_model_rax,x86_model_rflags,bytes(output+output_size,10),bytes(x86_model_rsp,8);
modifies output_size,native_address_site,native_boolean_end,native_boolean_start,native_boolean_cc,
    x86_model_rip,x86_model_rsp,x86_model_rcx,x86_model_rax,x86_model_rflags,bytes(output+output_size,10);
ensures result==1 && x86_model_rip==old(output+output_size)+10 && x86_model_rsp==old(x86_model_rsp)+8;
ensures x86_model_rcx==old(load64(x86_model_rsp));
ensures x86_model_rax==(x86_model_rcx <= old(x86_model_rax));
ensures (x86_model_rflags&(~0x8d5))==(old(x86_model_rflags)&(~0x8d5));
fn x86_emit_and_model_le() {
    x86_model_rip=output+output_size;
    let top=load64(x86_model_rsp);
    let right=x86_model_rax;
    proof {
        assert output_size < output_limit;
        assert output_size+1 < output_limit;
        assert output_size+2 < output_limit;
        assert output_size+3 < output_limit;
        assert output_size+4 < output_limit;
        assert output_size+5 < output_limit;
        assert output_size+6 < output_limit;
        assert output_size+7 < output_limit;
        assert output_size+8 < output_limit;
        assert output_size+9 < output_limit;
    }
    native_binary(261);
    proof {
        assert load8(x86_model_rip)==0x59;
    }
    let word=load64(x86_model_rsp);
    assert word==top;
    let vm_result=vm_binary(261,word,x86_model_rax);
    x86_model_pop_decoded(word);
    assert x86_model_rcx==top;
    assert x86_model_rax==right;
    proof {
        assert load8(x86_model_rip)==0x48;
        assert load8(x86_model_rip+1)==0x39;
        assert load8(x86_model_rip+2)==0xc1;
    }
    x86_model_compare_decoded();
    let flags=x86_model_sub_flags(word,right,word-right);
    assert (x86_model_rflags&0x8d5)==flags;
    let condition=x86_test_condition(158,flags);
    proof {x86_compare_conditions(word,right);}
    assert condition==vm_result;
    proof {
        assert load8(x86_model_rip)==0x0f;
        assert load8(x86_model_rip+2)==0xc0;
    }
    let condition_code=load8(x86_model_rip+1);
    assert condition_code==158;
    x86_model_set_decoded(condition_code);
    assert (x86_model_rax&255)==condition;
    proof {
        assert load8(x86_model_rip)==0x0f;
        assert load8(x86_model_rip+1)==0xb6;
        assert load8(x86_model_rip+2)==0xc0;
    }
    x86_model_extend_decoded();
    assert x86_model_rax==vm_result;
    return 1;
}

requires native_binary_cached==0;
requires output_limit==67108864 || output_limit==268435456;
requires output_size>=0 && output_size<=output_limit-10;
requires output+output_size<=9223372036854775797;
requires x86_model_rsp>=0 && x86_model_rsp<=9223372036854775799;
requires writable_bytes(output+output_size,10);
requires readable_bytes(x86_model_rsp,8);
requires disjoint_bytes(output+output_size,4,x86_model_rsp,8);
requires disjoint_bytes(output+output_size+4,4,x86_model_rsp,8);
requires disjoint_bytes(output+output_size+8,2,x86_model_rsp,8);
reads native_binary_cached,output,output_size,output_limit,native_address_site,native_boolean_end,native_register_frame,frontend_language,native_boolean_start,native_boolean_cc,
    x86_model_rip,x86_model_rsp,x86_model_rcx,x86_model_rax,x86_model_rflags,bytes(output+output_size,10),bytes(x86_model_rsp,8);
modifies output_size,native_address_site,native_boolean_end,native_boolean_start,native_boolean_cc,
    x86_model_rip,x86_model_rsp,x86_model_rcx,x86_model_rax,x86_model_rflags,bytes(output+output_size,10);
ensures result==1 && x86_model_rip==old(output+output_size)+10 && x86_model_rsp==old(x86_model_rsp)+8;
ensures x86_model_rcx==old(load64(x86_model_rsp));
ensures x86_model_rax==(x86_model_rcx > old(x86_model_rax));
ensures (x86_model_rflags&(~0x8d5))==(old(x86_model_rflags)&(~0x8d5));
fn x86_emit_and_model_gt() {
    x86_model_rip=output+output_size;
    let top=load64(x86_model_rsp);
    let right=x86_model_rax;
    proof {
        assert output_size < output_limit;
        assert output_size+1 < output_limit;
        assert output_size+2 < output_limit;
        assert output_size+3 < output_limit;
        assert output_size+4 < output_limit;
        assert output_size+5 < output_limit;
        assert output_size+6 < output_limit;
        assert output_size+7 < output_limit;
        assert output_size+8 < output_limit;
        assert output_size+9 < output_limit;
    }
    native_binary(62);
    proof {
        assert load8(x86_model_rip)==0x59;
    }
    let word=load64(x86_model_rsp);
    assert word==top;
    let vm_result=vm_binary(62,word,x86_model_rax);
    x86_model_pop_decoded(word);
    assert x86_model_rcx==top;
    assert x86_model_rax==right;
    proof {
        assert load8(x86_model_rip)==0x48;
        assert load8(x86_model_rip+1)==0x39;
        assert load8(x86_model_rip+2)==0xc1;
    }
    x86_model_compare_decoded();
    let flags=x86_model_sub_flags(word,right,word-right);
    assert (x86_model_rflags&0x8d5)==flags;
    let condition=x86_test_condition(159,flags);
    proof {x86_compare_conditions(word,right);}
    assert condition==vm_result;
    proof {
        assert load8(x86_model_rip)==0x0f;
        assert load8(x86_model_rip+2)==0xc0;
    }
    let condition_code=load8(x86_model_rip+1);
    assert condition_code==159;
    x86_model_set_decoded(condition_code);
    assert (x86_model_rax&255)==condition;
    proof {
        assert load8(x86_model_rip)==0x0f;
        assert load8(x86_model_rip+1)==0xb6;
        assert load8(x86_model_rip+2)==0xc0;
    }
    x86_model_extend_decoded();
    assert x86_model_rax==vm_result;
    return 1;
}
