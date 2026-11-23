import "x86-addition-model.flex";

// The caller supplies an arbitrary value for the undefined auxiliary flag.
fn x86_model_logic_step(undefined_af) {
    let pc=x86_model_rip;
    if load8(pc)!=0x48 {return 0;}
    if load8(pc+2)!=0xc8 {return 0;}
    let operation=load8(pc+1);
    let result=0;
    if operation==0x21 {result=x86_model_rax&x86_model_rcx;}
    else if operation==0x09 {result=x86_model_rax|x86_model_rcx;}
    else if operation==0x31 {result=x86_model_rax^x86_model_rcx;}
    else {return 0;}
    x86_model_rflags=(x86_model_rflags&(~0x8d5))|x86_model_add_flags(result,0,result)|((undefined_af&1)<<4);
    x86_model_rax=result;
    x86_model_rip=pc+3;
    return 1;
}

requires native_binary_cached==0;
requires output_limit==67108864 || output_limit==268435456;
requires output_size>=0 && output_size<=output_limit-4;
requires output+output_size<=9223372036854775803;
requires x86_model_rsp>=0 && x86_model_rsp<=9223372036854775799;
requires writable_bytes(output+output_size,4);
requires readable_bytes(x86_model_rsp,8);
requires disjoint_bytes(output+output_size,4,x86_model_rsp,8);
reads native_binary_cached,output,output_size,output_limit,native_address_site,native_boolean_end,native_address_kind,native_address_value,
    x86_model_rip,x86_model_rsp,x86_model_rcx,x86_model_rax,x86_model_rflags,bytes(output+output_size,4),bytes(x86_model_rsp,8);
modifies output_size,native_address_site,native_boolean_end,native_address_kind,native_address_value,
    x86_model_rip,x86_model_rsp,x86_model_rcx,x86_model_rax,x86_model_rflags,bytes(output+output_size,4);
ensures result==1 && x86_model_rip==old(output+output_size)+4 && x86_model_rsp==old(x86_model_rsp)+8;
ensures x86_model_rcx==old(load64(x86_model_rsp));
ensures x86_model_rax==(old(x86_model_rax) & x86_model_rcx);
ensures (x86_model_rflags&(~0x8d5))==(old(x86_model_rflags)&(~0x8d5));
ensures !(x86_model_rflags&0x801);
ensures ((x86_model_rflags>>4)&1)==(undefined_af&1);
fn x86_emit_and_model_and(undefined_af) {
    let code=output+output_size;
    x86_model_rip=code;
    let stack_top=load64(x86_model_rsp);
    let initial_acc=x86_model_rax;
    let vm_result=vm_binary(38,stack_top,x86_model_rax);
    assert vm_result==(initial_acc & stack_top);
    proof {
        assert output_size < output_limit;
        assert output_size+1 < output_limit;
        assert output_size+2 < output_limit;
        assert output_size+3 < output_limit;
    }
    native_binary(38);
    proof {
        assert load8(x86_model_rip)==0x59;
        assert load8(x86_model_rip+1)==0x48;
        assert load8(x86_model_rip+2)==0x21;
        assert load8(x86_model_rip+3)==0xc8;
        assert load64(x86_model_rsp)==stack_top;
    }
    let popped=x86_model_step();
    assert popped==1;
    assert x86_model_rcx==stack_top;
    assert x86_model_rax==initial_acc;
    proof {
        assert load8(x86_model_rip)==0x48;
        assert load8(x86_model_rip+1)==0x21;
        assert load8(x86_model_rip+2)==0xc8;
    }
    let executed=x86_model_logic_step(undefined_af);
    assert executed==1;
    assert x86_model_rax==vm_result;
    return executed;
}

requires native_binary_cached==0;
requires output_limit==67108864 || output_limit==268435456;
requires output_size>=0 && output_size<=output_limit-4;
requires output+output_size<=9223372036854775803;
requires x86_model_rsp>=0 && x86_model_rsp<=9223372036854775799;
requires writable_bytes(output+output_size,4);
requires readable_bytes(x86_model_rsp,8);
requires disjoint_bytes(output+output_size,4,x86_model_rsp,8);
reads native_binary_cached,output,output_size,output_limit,native_address_site,native_boolean_end,native_address_kind,native_address_value,
    x86_model_rip,x86_model_rsp,x86_model_rcx,x86_model_rax,x86_model_rflags,bytes(output+output_size,4),bytes(x86_model_rsp,8);
modifies output_size,native_address_site,native_boolean_end,native_address_kind,native_address_value,
    x86_model_rip,x86_model_rsp,x86_model_rcx,x86_model_rax,x86_model_rflags,bytes(output+output_size,4);
ensures result==1 && x86_model_rip==old(output+output_size)+4 && x86_model_rsp==old(x86_model_rsp)+8;
ensures x86_model_rcx==old(load64(x86_model_rsp));
ensures x86_model_rax==(old(x86_model_rax) | x86_model_rcx);
ensures (x86_model_rflags&(~0x8d5))==(old(x86_model_rflags)&(~0x8d5));
ensures !(x86_model_rflags&0x801);
ensures ((x86_model_rflags>>4)&1)==(undefined_af&1);
fn x86_emit_and_model_or(undefined_af) {
    let code=output+output_size;
    x86_model_rip=code;
    let stack_top=load64(x86_model_rsp);
    let initial_acc=x86_model_rax;
    let vm_result=vm_binary(124,stack_top,x86_model_rax);
    assert vm_result==(initial_acc | stack_top);
    proof {
        assert output_size < output_limit;
        assert output_size+1 < output_limit;
        assert output_size+2 < output_limit;
        assert output_size+3 < output_limit;
    }
    native_binary(124);
    proof {
        assert load8(x86_model_rip)==0x59;
        assert load8(x86_model_rip+1)==0x48;
        assert load8(x86_model_rip+2)==0x09;
        assert load8(x86_model_rip+3)==0xc8;
        assert load64(x86_model_rsp)==stack_top;
    }
    let popped=x86_model_step();
    assert popped==1;
    assert x86_model_rcx==stack_top;
    assert x86_model_rax==initial_acc;
    proof {
        assert load8(x86_model_rip)==0x48;
        assert load8(x86_model_rip+1)!=0x21;
        assert load8(x86_model_rip+1)==0x09;
        assert load8(x86_model_rip+2)==0xc8;
    }
    let executed=x86_model_logic_step(undefined_af);
    assert executed==1;
    assert x86_model_rax==vm_result;
    return executed;
}

requires native_binary_cached==0;
requires output_limit==67108864 || output_limit==268435456;
requires output_size>=0 && output_size<=output_limit-4;
requires output+output_size<=9223372036854775803;
requires x86_model_rsp>=0 && x86_model_rsp<=9223372036854775799;
requires writable_bytes(output+output_size,4);
requires readable_bytes(x86_model_rsp,8);
requires disjoint_bytes(output+output_size,4,x86_model_rsp,8);
reads native_binary_cached,output,output_size,output_limit,native_address_site,native_boolean_end,native_address_kind,native_address_value,
    x86_model_rip,x86_model_rsp,x86_model_rcx,x86_model_rax,x86_model_rflags,bytes(output+output_size,4),bytes(x86_model_rsp,8);
modifies output_size,native_address_site,native_boolean_end,native_address_kind,native_address_value,
    x86_model_rip,x86_model_rsp,x86_model_rcx,x86_model_rax,x86_model_rflags,bytes(output+output_size,4);
ensures result==1 && x86_model_rip==old(output+output_size)+4 && x86_model_rsp==old(x86_model_rsp)+8;
ensures x86_model_rcx==old(load64(x86_model_rsp));
ensures x86_model_rax==(old(x86_model_rax) ^ x86_model_rcx);
ensures (x86_model_rflags&(~0x8d5))==(old(x86_model_rflags)&(~0x8d5));
ensures !(x86_model_rflags&0x801);
ensures ((x86_model_rflags>>4)&1)==(undefined_af&1);
fn x86_emit_and_model_xor(undefined_af) {
    let code=output+output_size;
    x86_model_rip=code;
    let stack_top=load64(x86_model_rsp);
    let initial_acc=x86_model_rax;
    let vm_result=vm_binary(94,stack_top,x86_model_rax);
    assert vm_result==(initial_acc ^ stack_top);
    proof {
        assert output_size < output_limit;
        assert output_size+1 < output_limit;
        assert output_size+2 < output_limit;
        assert output_size+3 < output_limit;
    }
    native_binary(94);
    proof {
        assert load8(x86_model_rip)==0x59;
        assert load8(x86_model_rip+1)==0x48;
        assert load8(x86_model_rip+2)==0x31;
        assert load8(x86_model_rip+3)==0xc8;
        assert load64(x86_model_rsp)==stack_top;
    }
    let popped=x86_model_step();
    assert popped==1;
    assert x86_model_rcx==stack_top;
    assert x86_model_rax==initial_acc;
    proof {
        assert load8(x86_model_rip)==0x48;
        assert load8(x86_model_rip+1)!=0x21;
        assert load8(x86_model_rip+1)!=0x09;
        assert load8(x86_model_rip+1)==0x31;
        assert load8(x86_model_rip+2)==0xc8;
    }
    let executed=x86_model_logic_step(undefined_af);
    assert executed==1;
    assert x86_model_rax==vm_result;
    return executed;
}
