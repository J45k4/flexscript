import "x86-addition-model.flex";

fn x86_model_sub_flags(left,right,difference) {
    let sign=0x8000000000000000;
    let carry=(left^sign)<(right^sign);
    let overflow=((left^right)&(left^difference))<0;
    let auxiliary=((left^right^difference)>>4)&1;
    return x86_model_add_flags(difference,0,difference)|carry|(auxiliary<<4)|(overflow<<11);
}

fn x86_model_subtract_step() {
    let pc=x86_model_rip;
    if load8(pc)!=0x48 {return 0;}
    if load8(pc+1)!=0x29 {return 0;}
    if load8(pc+2)!=0xc1 {return 0;}
    let difference=x86_model_rcx-x86_model_rax;
    x86_model_rflags=(x86_model_rflags&(~0x8d5))|x86_model_sub_flags(x86_model_rcx,x86_model_rax,difference);
    x86_model_rcx=difference;
    x86_model_rip=pc+3;
    return 1;
}

fn x86_model_move_step() {
    let pc=x86_model_rip;
    if load8(pc)!=0x48 {return 0;}
    if load8(pc+1)!=0x89 {return 0;}
    if load8(pc+2)!=0xc8 {return 0;}
    x86_model_rax=x86_model_rcx;
    x86_model_rip=pc+3;
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
ensures x86_model_rcx==old(load64(x86_model_rsp))-old(x86_model_rax);
ensures x86_model_rax==x86_model_rcx;
ensures (x86_model_rflags&(~0x8d5))==(old(x86_model_rflags)&(~0x8d5));

fn x86_emit_and_model_subtract() {
    x86_model_rip=output+output_size;
    let top=load64(x86_model_rsp);
    let vm_result=vm_binary(45,top,x86_model_rax);
    proof {
        assert output_size < output_limit;
        assert output_size+1 < output_limit;
        assert output_size+2 < output_limit;
        assert output_size+3 < output_limit;
        assert output_size+4 < output_limit;
        assert output_size+5 < output_limit;
        assert output_size+6 < output_limit;
    }
    native_binary(45);
    proof {
        assert load8(x86_model_rip)==0x59;
        assert load64(x86_model_rsp)==top;
    }
    let popped=x86_model_step();
    assert popped==1;
    proof {
        assert load8(x86_model_rip)==0x48;
        assert load8(x86_model_rip+1)==0x29;
        assert load8(x86_model_rip+2)==0xc1;
    }
    let subtracted=x86_model_subtract_step();
    assert subtracted==1;
    proof {
        assert load8(x86_model_rip)==0x48;
        assert load8(x86_model_rip+1)==0x89;
        assert load8(x86_model_rip+2)==0xc8;
    }
    let moved=x86_model_move_step();
    assert x86_model_rax==vm_result;
    return moved;
}
