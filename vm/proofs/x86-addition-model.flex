import "../../compiler/x86-emission.flex";
import "../word-operations.flex";

// Projected machine state for normal execution of the two encodings.
// The executable mapping, paging, and exceptional hardware behavior are
// outside this model. Low-word arithmetic uses modulo 2^64 semantics.
// Intel SDM Volume 2, ADD and POP. See docs/vm-verification.md.
global x86_model_rip=0;
global x86_model_rsp=0;
global x86_model_rcx=0;
global x86_model_rax=0;
global x86_model_rflags=0;

fn x86_model_add_flags(a,b,sum) {
    let sign=0x8000000000000000;
    let carry=(sum^sign)<(a^sign);
    let overflow=((a^sum)&(b^sum))<0;
    let auxiliary=((a^b^sum)>>4)&1;
    let parity=sum&255;
    parity=parity^(parity>>4);
    parity=parity^(parity>>2);
    parity=parity^(parity>>1);
    return carry | (((parity&1)^1)<<2) | (auxiliary<<4)
        | ((sum==0)<<6) | ((sum<0)<<7) | (overflow<<11);
}

fn x86_model_step() {
    let pc=x86_model_rip;
    let opcode=load8(pc);
    if opcode==0x59 {
        x86_model_rcx=load64(x86_model_rsp);
        x86_model_rsp=x86_model_rsp+8;
        x86_model_rip=pc+1;
        return 1;
    }
    if opcode==0x48 && load8(pc+1)==0x01 && load8(pc+2)==0xc8 {
        let sum=x86_model_rax+x86_model_rcx;
        x86_model_rflags=(x86_model_rflags&(~0x8d5))|x86_model_add_flags(x86_model_rax,x86_model_rcx,sum);
        x86_model_rax=sum;
        x86_model_rip=pc+3;
        return 1;
    }
    return 0;
}

requires readable_bytes(x86_model_rip,4) && readable_bytes(x86_model_rsp,8);
requires x86_model_rip>=0 && x86_model_rip<=9223372036854775803;
requires x86_model_rsp>=0 && x86_model_rsp<=9223372036854775799;
requires load8(x86_model_rip)==0x59;
requires load8(x86_model_rip+1)==0x48;
requires load8(x86_model_rip+2)==0x01;
requires load8(x86_model_rip+3)==0xc8;
reads x86_model_rip,x86_model_rsp,x86_model_rcx,x86_model_rax,x86_model_rflags,bytes(x86_model_rip,4),bytes(x86_model_rsp,8);
modifies x86_model_rip,x86_model_rsp,x86_model_rcx,x86_model_rax,x86_model_rflags;
ensures result==1 && x86_model_rip==old(x86_model_rip)+4 && x86_model_rsp==old(x86_model_rsp)+8;
ensures x86_model_rcx==old(load64(x86_model_rsp));
ensures x86_model_rax==old(x86_model_rax)+old(load64(x86_model_rsp));
ensures (x86_model_rflags&(~0x8d5))==(old(x86_model_rflags)&(~0x8d5));
fn x86_model_addition() {
    let pc=x86_model_rip;
    let sp=x86_model_rsp;
    let a=x86_model_rax;
    let top=load64(sp);
    proof {
        assert load8(x86_model_rip)==0x59;
    }
    let popped=x86_model_step();
    assert popped==1;
    proof {
        assert x86_model_rip==pc+1;
        assert x86_model_rsp==sp+8;
        assert x86_model_rcx==top;
        assert x86_model_rax==a;
        assert load8(x86_model_rip)!=0x59;
        assert load8(x86_model_rip)==0x48;
        assert load8(x86_model_rip+1)==0x01;
        assert load8(x86_model_rip+2)==0xc8;
    }
    return x86_model_step();
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
ensures x86_model_rax==old(x86_model_rax)+x86_model_rcx;
ensures (x86_model_rflags&(~0x8d5))==(old(x86_model_rflags)&(~0x8d5));
fn x86_emit_and_model_addition() {
    let code=output+output_size;
    x86_model_rip=code;
    let stack_top=load64(x86_model_rsp);
    let vm_result=vm_binary(43,stack_top,x86_model_rax);
    proof {
        assert output_size < output_limit;
        assert output_size+1 < output_limit;
        assert output_size+2 < output_limit;
        assert output_size+3 < output_limit;
    }
    native_binary(43);
    proof {
        assert load8(x86_model_rip)==0x59;
        assert load8(x86_model_rip+1)==0x48;
        assert load8(x86_model_rip+2)==0x01;
        assert load8(x86_model_rip+3)==0xc8;
        assert load64(x86_model_rsp)==stack_top;
    }
    let popped=x86_model_step();
    assert popped==1;
    proof {
        assert load8(x86_model_rip)!=0x59;
        assert load8(x86_model_rip)==0x48;
        assert load8(x86_model_rip+1)==0x01;
        assert load8(x86_model_rip+2)==0xc8;
    }
    let executed=x86_model_step();
    assert x86_model_rax==vm_result;
    return executed;
}
