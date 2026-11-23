import "x86-addition-model.flex";

global x86_model_rdi=0;
global x86_model_rdx=0;

// The guard's decision for the modeled TEST, CMP, and conditional branches.
// Its emitted bytes and the relocated targets need a separate refinement.
reads nothing;
modifies nothing;
ensures result==(right==0 || (left==0x8000000000000000 && right==(-1)));
fn x86_model_division_guard(left,right) {
    if (right&right)==0 {return 1;}
    if (left-0x8000000000000000)!=0 {return 0;}
    return (right-(-1))==0;
}

// CQO supplies the sign-extended high word before these modeled IDIV effects.
fn x86_model_idiv_sign_extended(undefined_flags) {
    let dividend=x86_model_rax;
    let divisor=x86_model_rdi;
    x86_model_rax=dividend/divisor;
    x86_model_rdx=dividend%divisor;
    x86_model_rflags=(x86_model_rflags&(~0x8d5))|(undefined_flags&0x8d5);
    x86_model_rip=x86_model_rip+3;
}

// The quotient remains in RAX after IDIV.
requires native_binary_cached==0;
requires output_limit==67108864 || output_limit==268435456;
requires output_size>=0 && output_size<=output_limit-12;
requires output+output_size<=9223372036854775795;
requires x86_model_rsp>=0 && x86_model_rsp<=9223372036854775799;
requires writable_bytes(output+output_size,12);
requires readable_bytes(x86_model_rsp,8);
requires x86_model_rax!=0;
requires (x86_model_rax!=(-1)) | (load64(x86_model_rsp)!=0x8000000000000000);
requires disjoint_bytes(output+output_size,4,x86_model_rsp,8);
requires disjoint_bytes(output+output_size+4,4,x86_model_rsp,8);
requires disjoint_bytes(output+output_size+8,4,x86_model_rsp,8);
reads native_binary_cached,output,output_size,output_limit,native_address_site,native_boolean_end,vm_error,
    x86_model_rip,x86_model_rsp,x86_model_rcx,x86_model_rax,x86_model_rdi,x86_model_rdx,x86_model_rflags,
    bytes(output+output_size,12),bytes(x86_model_rsp,8);
modifies output_size,native_address_site,native_boolean_end,
    x86_model_rip,x86_model_rsp,x86_model_rcx,x86_model_rax,x86_model_rdi,x86_model_rdx,x86_model_rflags,
    bytes(output+output_size,12);
ensures result==1 && x86_model_rip==old(output+output_size)+12 && x86_model_rsp==old(x86_model_rsp)+8;
ensures x86_model_rcx==old(load64(x86_model_rsp)) && x86_model_rdi==old(x86_model_rax);
ensures x86_model_rax==(x86_model_rcx / x86_model_rdi);
ensures x86_model_rdx==(x86_model_rcx % x86_model_rdi);
ensures (x86_model_rflags&(~0x8d5))==(old(x86_model_rflags)&(~0x8d5));
ensures (x86_model_rflags&0x8d5)==(undefined_flags&0x8d5);
fn x86_emit_and_model_divide(undefined_flags) {
    x86_model_rip=output+output_size;
    let original=load64(x86_model_rsp);
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
        assert output_size+10 < output_limit;
        assert output_size+11 < output_limit;
    }
    native_binary(47);
    proof {assert load8(x86_model_rip)==0x59;}
    let word=load64(x86_model_rsp);
    assert word==original;
    let rejected=x86_model_division_guard(word,x86_model_rax);
    assert !rejected;
    let result=vm_binary(47,word,x86_model_rax);
    x86_model_rcx=word;
    x86_model_rsp=x86_model_rsp+8;
    x86_model_rip=x86_model_rip+1;
    proof {
        assert load8(x86_model_rip)==72;
        assert load8(x86_model_rip+1)==137;
        assert load8(x86_model_rip+2)==199;
    }
    x86_model_rdi=x86_model_rax;
    x86_model_rip=x86_model_rip+3;
    proof {
        assert load8(x86_model_rip)==72;
        assert load8(x86_model_rip+1)==137;
        assert load8(x86_model_rip+2)==200;
    }
    x86_model_rax=x86_model_rcx;
    x86_model_rip=x86_model_rip+3;
    proof {
        assert load8(x86_model_rip)==72;
        assert load8(x86_model_rip+1)==153;
    }
    x86_model_rdx=x86_model_rax>>63;
    x86_model_rip=x86_model_rip+2;
    proof {
        assert load8(x86_model_rip)==72;
        assert load8(x86_model_rip+1)==247;
        assert load8(x86_model_rip+2)==255;
    }
    assert x86_model_rdx==(x86_model_rax>>63);
    x86_model_idiv_sign_extended(undefined_flags);
    assert x86_model_rax==result;
    return 1;
}

// The remainder moves from RDX to RAX after IDIV.
requires native_binary_cached==0;
requires output_limit==67108864 || output_limit==268435456;
requires output_size>=0 && output_size<=output_limit-15;
requires output+output_size<=9223372036854775792;
requires x86_model_rsp>=0 && x86_model_rsp<=9223372036854775799;
requires writable_bytes(output+output_size,15);
requires readable_bytes(x86_model_rsp,8);
requires x86_model_rax!=0;
requires (x86_model_rax!=(-1)) | (load64(x86_model_rsp)!=0x8000000000000000);
requires disjoint_bytes(output+output_size,4,x86_model_rsp,8);
requires disjoint_bytes(output+output_size+4,4,x86_model_rsp,8);
requires disjoint_bytes(output+output_size+8,4,x86_model_rsp,8);
requires disjoint_bytes(output+output_size+12,3,x86_model_rsp,8);
reads native_binary_cached,output,output_size,output_limit,native_address_site,native_boolean_end,vm_error,
    x86_model_rip,x86_model_rsp,x86_model_rcx,x86_model_rax,x86_model_rdi,x86_model_rdx,x86_model_rflags,
    bytes(output+output_size,15),bytes(x86_model_rsp,8);
modifies output_size,native_address_site,native_boolean_end,
    x86_model_rip,x86_model_rsp,x86_model_rcx,x86_model_rax,x86_model_rdi,x86_model_rdx,x86_model_rflags,
    bytes(output+output_size,15);
ensures result==1 && x86_model_rip==old(output+output_size)+15 && x86_model_rsp==old(x86_model_rsp)+8;
ensures x86_model_rcx==old(load64(x86_model_rsp)) && x86_model_rdi==old(x86_model_rax);
ensures x86_model_rax==(x86_model_rcx % x86_model_rdi);
ensures x86_model_rdx==(x86_model_rcx % x86_model_rdi);
ensures (x86_model_rflags&(~0x8d5))==(old(x86_model_rflags)&(~0x8d5));
ensures (x86_model_rflags&0x8d5)==(undefined_flags&0x8d5);
fn x86_emit_and_model_remainder(undefined_flags) {
    x86_model_rip=output+output_size;
    let original=load64(x86_model_rsp);
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
        assert output_size+10 < output_limit;
        assert output_size+11 < output_limit;
        assert output_size+12 < output_limit;
        assert output_size+13 < output_limit;
        assert output_size+14 < output_limit;
    }
    native_binary(37);
    proof {assert load8(x86_model_rip)==0x59;}
    let word=load64(x86_model_rsp);
    assert word==original;
    let rejected=x86_model_division_guard(word,x86_model_rax);
    assert !rejected;
    let result=vm_binary(37,word,x86_model_rax);
    x86_model_rcx=word;
    x86_model_rsp=x86_model_rsp+8;
    x86_model_rip=x86_model_rip+1;
    proof {
        assert load8(x86_model_rip)==72;
        assert load8(x86_model_rip+1)==137;
        assert load8(x86_model_rip+2)==199;
    }
    x86_model_rdi=x86_model_rax;
    x86_model_rip=x86_model_rip+3;
    proof {
        assert load8(x86_model_rip)==72;
        assert load8(x86_model_rip+1)==137;
        assert load8(x86_model_rip+2)==200;
    }
    x86_model_rax=x86_model_rcx;
    x86_model_rip=x86_model_rip+3;
    proof {
        assert load8(x86_model_rip)==72;
        assert load8(x86_model_rip+1)==153;
    }
    x86_model_rdx=x86_model_rax>>63;
    x86_model_rip=x86_model_rip+2;
    proof {
        assert load8(x86_model_rip)==72;
        assert load8(x86_model_rip+1)==247;
        assert load8(x86_model_rip+2)==255;
    }
    assert x86_model_rdx==(x86_model_rax>>63);
    x86_model_idiv_sign_extended(undefined_flags);
    proof {
        assert load8(x86_model_rip)==72;
        assert load8(x86_model_rip+1)==137;
        assert load8(x86_model_rip+2)==208;
    }
    x86_model_rax=x86_model_rdx;
    x86_model_rip=x86_model_rip+3;
    assert x86_model_rax==result;
    return 1;
}
