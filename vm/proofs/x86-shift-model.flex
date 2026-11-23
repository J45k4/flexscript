import "x86-addition-model.flex";

fn x86_model_exchange_step() {
    let pc=x86_model_rip;
    if load8(pc)!=0x48 {return 0;}
    if load8(pc+1)!=0x87 {return 0;}
    if load8(pc+2)!=0xc8 {return 0;}
    let prior=x86_model_rax;
    x86_model_rax=x86_model_rcx;
    x86_model_rcx=prior;
    x86_model_rip=pc+3;
    return 1;
}

// CL supplies the count. The input flags word supplies arbitrary values for
// the flags left undefined by a nonzero shift.
fn x86_model_shift_step(unspecified_flags) {
    let pc=x86_model_rip;
    if load8(pc)!=0x48 {return 0;}
    if load8(pc+1)!=0xd3 {return 0;}
    let operand=load8(pc+2);
    let count=x86_model_rcx&63;
    let before=x86_model_rax;
    if operand==0xe0 {
        let result=before<<count;
        let carry=(before>>(64-count))&1;
        let overflow=(unspecified_flags>>11)&1;
        if count==1 {overflow=(result<0)^carry;}
        return x86_model_finish_shift(result,count,carry,overflow,unspecified_flags);
    }
    if operand==0xf8 {
        let result=before>>count;
        let carry=(before>>(count-1))&1;
        let overflow=(unspecified_flags>>11)&1;
        if count==1 {overflow=0;}
        return x86_model_finish_shift(result,count,carry,overflow,unspecified_flags);
    }
    return 0;
}

fn x86_model_finish_shift(result,count,carry,overflow,unspecified_flags) {
    if count {
        x86_model_rflags=(x86_model_rflags&(~0x8d5))|x86_model_add_flags(result,0,result)
            |carry|(unspecified_flags&0x10)|(overflow<<11);
    }
    x86_model_rax=result;
    x86_model_rip=x86_model_rip+3;
    return 1;
}

requires native_binary_cached==0;
requires output_limit==67108864 || output_limit==268435456;
requires output_size>=0 && output_size<=output_limit-7;
requires output+output_size<=9223372036854775800;
requires x86_model_rsp>=0 && x86_model_rsp<=9223372036854775799;
requires writable_bytes(output+output_size,7);
requires readable_bytes(x86_model_rsp,8);
// The two spans cover all seven emitted bytes and keep both separation
// predicates within the verifier's bounded bytewise expansion.
requires disjoint_bytes(output+output_size,4,x86_model_rsp,8);
requires disjoint_bytes(output+output_size+4,3,x86_model_rsp,8);
reads native_binary_cached,output,output_size,output_limit,native_address_site,native_boolean_end,native_address_kind,native_address_value,
    x86_model_rip,x86_model_rsp,x86_model_rcx,x86_model_rax,x86_model_rflags,bytes(output+output_size,7),bytes(x86_model_rsp,8);
modifies output_size,native_address_site,native_boolean_end,native_address_kind,native_address_value,
    x86_model_rip,x86_model_rsp,x86_model_rcx,x86_model_rax,x86_model_rflags,bytes(output+output_size,7);
ensures result==1 && x86_model_rip==old(output+output_size)+7 && x86_model_rsp==old(x86_model_rsp)+8;
ensures x86_model_rcx==old(x86_model_rax);
ensures x86_model_rax==(old(load64(x86_model_rsp)) << (old(x86_model_rax)&63));
ensures (x86_model_rcx&63)!=0 || x86_model_rflags==old(x86_model_rflags);
ensures (x86_model_rflags&(~0x8d5))==(old(x86_model_rflags)&(~0x8d5));

fn x86_emit_and_model_shift_left(unspecified_flags) {
    x86_model_rip=output+output_size;
    let top=load64(x86_model_rsp);
    let vm_result=vm_binary(265,top,x86_model_rax);
    proof {
        assert output_size < output_limit;
        assert output_size+1 < output_limit;
        assert output_size+2 < output_limit;
        assert output_size+3 < output_limit;
        assert output_size+4 < output_limit;
        assert output_size+5 < output_limit;
        assert output_size+6 < output_limit;
    }
    native_binary(265);
    proof {
        assert load8(x86_model_rip)==0x59;
        assert load64(x86_model_rsp)==top;
    }
    let popped=x86_model_step();
    assert popped==1;
    proof {
        assert load8(x86_model_rip)==0x48;
        assert load8(x86_model_rip+1)==0x87;
        assert load8(x86_model_rip+2)==0xc8;
    }
    let exchanged=x86_model_exchange_step();
    assert exchanged==1;
    proof {
        assert load8(x86_model_rip)==0x48;
        assert load8(x86_model_rip+1)==0xd3;
        assert load8(x86_model_rip+2)==0xe0;
        assert load8(x86_model_rip+2)!=0xf8;
    }
    let shifted=x86_model_shift_step(unspecified_flags);
    assert x86_model_rax==vm_result;
    return shifted;
}

requires native_binary_cached==0;
requires output_limit==67108864 || output_limit==268435456;
requires output_size>=0 && output_size<=output_limit-7;
requires output+output_size<=9223372036854775800;
requires x86_model_rsp>=0 && x86_model_rsp<=9223372036854775799;
requires writable_bytes(output+output_size,7);
requires readable_bytes(x86_model_rsp,8);
// The two spans cover all seven emitted bytes and keep both separation
// predicates within the verifier's bounded bytewise expansion.
requires disjoint_bytes(output+output_size,4,x86_model_rsp,8);
requires disjoint_bytes(output+output_size+4,3,x86_model_rsp,8);
reads native_binary_cached,output,output_size,output_limit,native_address_site,native_boolean_end,native_address_kind,native_address_value,
    x86_model_rip,x86_model_rsp,x86_model_rcx,x86_model_rax,x86_model_rflags,bytes(output+output_size,7),bytes(x86_model_rsp,8);
modifies output_size,native_address_site,native_boolean_end,native_address_kind,native_address_value,
    x86_model_rip,x86_model_rsp,x86_model_rcx,x86_model_rax,x86_model_rflags,bytes(output+output_size,7);
ensures result==1 && x86_model_rip==old(output+output_size)+7 && x86_model_rsp==old(x86_model_rsp)+8;
ensures x86_model_rcx==old(x86_model_rax);
ensures x86_model_rax==(old(load64(x86_model_rsp)) >> (old(x86_model_rax)&63));
ensures (x86_model_rcx&63)!=0 || x86_model_rflags==old(x86_model_rflags);
ensures (x86_model_rflags&(~0x8d5))==(old(x86_model_rflags)&(~0x8d5));

fn x86_emit_and_model_shift_right(unspecified_flags) {
    x86_model_rip=output+output_size;
    let top=load64(x86_model_rsp);
    let vm_result=vm_binary(266,top,x86_model_rax);
    proof {
        assert output_size < output_limit;
        assert output_size+1 < output_limit;
        assert output_size+2 < output_limit;
        assert output_size+3 < output_limit;
        assert output_size+4 < output_limit;
        assert output_size+5 < output_limit;
        assert output_size+6 < output_limit;
    }
    native_binary(266);
    proof {
        assert load8(x86_model_rip)==0x59;
        assert load64(x86_model_rsp)==top;
    }
    let popped=x86_model_step();
    assert popped==1;
    proof {
        assert load8(x86_model_rip)==0x48;
        assert load8(x86_model_rip+1)==0x87;
        assert load8(x86_model_rip+2)==0xc8;
    }
    let exchanged=x86_model_exchange_step();
    assert exchanged==1;
    proof {
        assert load8(x86_model_rip)==0x48;
        assert load8(x86_model_rip+1)==0xd3;
        assert load8(x86_model_rip+2)==0xf8;
        assert load8(x86_model_rip+2)!=0xe0;
    }
    let shifted=x86_model_shift_step(unspecified_flags);
    assert x86_model_rax==vm_result;
    return shifted;
}
