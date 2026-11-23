import "x86-addition-model.flex";

// The four unsigned 32-bit products supply the high half of the wide
// product. The correction terms reinterpret both inputs as signed words.
fn x86_model_signed_product_high(left,right) {
    let half=0xffffffff;
    let a0=left&half;let a1=(left>>32)&half;
    let b0=right&half;let b1=(right>>32)&half;
    let low=a0*b0;
    let cross_left=a0*b1;
    let cross_right=a1*b0;
    let middle=((low>>32)&half)+(cross_left&half)+(cross_right&half);
    let high=a1*b1+((cross_left>>32)&half)+((cross_right>>32)&half)+(middle>>32);
    // Each negative input subtracts its other operand from the high word.
    return high-(right&(left>>63))-(left&(right>>63));
}
// CF and OF report truncation. The remaining arithmetic flags are undefined.
fn x86_model_imul_decoded(unspecified_flags) {
    let left=x86_model_rcx;let right=x86_model_rax;
    let low=left*right;
    let high=x86_model_signed_product_high(left,right);
    let overflow=high!=(low>>63);
    x86_model_rflags=(x86_model_rflags&(~0x8d5))|(unspecified_flags&0xd4)|overflow|(overflow<<11);
    x86_model_rax=low;
    x86_model_rip=x86_model_rip+4;
}
requires native_binary_cached==0;
requires output_limit==67108864 || output_limit==268435456;
requires output_size>=0 && output_size<=output_limit-5;
requires output+output_size<=9223372036854775802;
requires x86_model_rsp>=0 && x86_model_rsp<=9223372036854775799;
requires writable_bytes(output+output_size,5);
requires readable_bytes(x86_model_rsp,8);
requires disjoint_bytes(output+output_size,4,x86_model_rsp,8);
requires disjoint_bytes(output+output_size+4,1,x86_model_rsp,8);
reads native_binary_cached,output,output_size,output_limit,native_address_site,native_boolean_end,
    x86_model_rip,x86_model_rsp,x86_model_rcx,x86_model_rax,x86_model_rflags,bytes(output+output_size,5),bytes(x86_model_rsp,8);
modifies output_size,native_address_site,native_boolean_end,
    x86_model_rip,x86_model_rsp,x86_model_rcx,x86_model_rax,x86_model_rflags,bytes(output+output_size,5);
ensures result==1 && x86_model_rip==old(output+output_size)+5 && x86_model_rsp==old(x86_model_rsp)+8;
ensures x86_model_rcx==old(load64(x86_model_rsp));
ensures x86_model_rax==x86_model_rcx*old(x86_model_rax);
ensures ((x86_model_rflags>>11)&1)==(x86_model_rflags&1);
ensures (x86_model_rflags&0xd4)==(unspecified_flags&0xd4);
ensures (x86_model_rflags&(~0x8d5))==(old(x86_model_rflags)&(~0x8d5));
fn x86_emit_and_model_multiply(unspecified_flags) {
    x86_model_rip=output+output_size;
    let top=load64(x86_model_rsp);
    proof {
        assert output_size < output_limit;
        assert output_size+1 < output_limit;
        assert output_size+2 < output_limit;
        assert output_size+3 < output_limit;
        assert output_size+4 < output_limit;
    }
    native_binary(42);
    proof {assert load8(x86_model_rip)==0x59;}
    let word=load64(x86_model_rsp);
    assert word==top;
    let result=vm_binary(42,word,x86_model_rax);
    let high=x86_model_signed_product_high(word,x86_model_rax);
    let truncated=high!=(result>>63);
    x86_model_rcx=word;
    x86_model_rsp=x86_model_rsp+8;
    x86_model_rip=x86_model_rip+1;
    proof {
        assert load8(x86_model_rip)==0x48;
        assert load8(x86_model_rip+1)==0x0f;
        assert load8(x86_model_rip+2)==0xaf;
        assert load8(x86_model_rip+3)==0xc1;
    }
    x86_model_imul_decoded(unspecified_flags);
    assert x86_model_rax==result;
    assert (x86_model_rflags&1)==truncated;
    return 1;
}
