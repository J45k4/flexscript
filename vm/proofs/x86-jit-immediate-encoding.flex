// Exact staged encodings of the three native immediate paths and their
// normal-execution x86-64 MOV model. CPU execution and RX publication are
// outside the source checker. The VM gate binds the emitter cases to source.
global output=0;
global vm_mode=0;
global output_size=0;
global output_limit=67108864;
global native_address_site=0;
global native_boolean_end=0;

global x86_mov_rip=0;
global x86_mov_rax=0;
global x86_mov_flags=0;
global x86_mov_rsp=0;

requires output_limit==67108864;
requires output_size>=0 && output_size<output_limit;
requires writable_bytes(output,67108864);
modifies output_size,native_address_site,native_boolean_end,bytes(output+output_size,1);
ensures output_size==old(output_size)+1;
ensures load8(output+old(output_size))==(b&255);
PRODUCTION_MOV_EMIT

requires output_limit==67108864;
requires output_size>=0 && output_size<=output_limit-4;
requires writable_bytes(output,67108864);
modifies output_size,native_address_site,native_boolean_end,bytes(output+output_size,4);
ensures output_size==old(output_size)+4;
ensures load8(output+old(output_size)+0)==((value>>0)&255);
ensures load8(output+old(output_size)+1)==((value>>8)&255);
ensures load8(output+old(output_size)+2)==((value>>16)&255);
ensures load8(output+old(output_size)+3)==((value>>24)&255);
fn emit32(value) {
    let i = 0;
    ghost let entered=output_size;
    invariant i>=0 && i<=4;
    invariant output_size==entered+i;
    invariant i<1 || load8(output+entered+0)==((value>>0)&255);
    invariant i<2 || load8(output+entered+1)==((value>>8)&255);
    invariant i<3 || load8(output+entered+2)==((value>>16)&255);
    invariant i<4 || load8(output+entered+3)==((value>>24)&255);
    decreases 4-i;
PRODUCTION_EMIT32_LOOP
    return 0;
}

requires output_limit==67108864;
requires output_size>=0 && output_size<=output_limit-8;
requires writable_bytes(output,67108864);
modifies output_size,native_address_site,native_boolean_end,bytes(output+output_size,8);
ensures output_size==old(output_size)+8;
ensures load8(output+old(output_size)+0)==((value>>0)&255);
ensures load8(output+old(output_size)+1)==((value>>8)&255);
ensures load8(output+old(output_size)+2)==((value>>16)&255);
ensures load8(output+old(output_size)+3)==((value>>24)&255);
ensures load8(output+old(output_size)+4)==((value>>32)&255);
ensures load8(output+old(output_size)+5)==((value>>40)&255);
ensures load8(output+old(output_size)+6)==((value>>48)&255);
ensures load8(output+old(output_size)+7)==((value>>56)&255);
fn emit64(value) {
    let i = 0;
    ghost let entered=output_size;
    invariant i>=0 && i<=8;
    invariant output_size==entered+i;
    invariant i<1 || load8(output+entered+0)==((value>>0)&255);
    invariant i<2 || load8(output+entered+1)==((value>>8)&255);
    invariant i<3 || load8(output+entered+2)==((value>>16)&255);
    invariant i<4 || load8(output+entered+3)==((value>>24)&255);
    invariant i<5 || load8(output+entered+4)==((value>>32)&255);
    invariant i<6 || load8(output+entered+5)==((value>>40)&255);
    invariant i<7 || load8(output+entered+6)==((value>>48)&255);
    invariant i<8 || load8(output+entered+7)==((value>>56)&255);
    decreases 8-i;
PRODUCTION_EMIT64_LOOP
    return 0;
}

requires readable_bytes(pc,4);
reads bytes(pc,4);
ensures result==(load8(pc) | (load8(pc+1)<<8) | (load8(pc+2)<<16) | (load8(pc+3)<<24));
fn x86_read_mov_u32(pc) {
    return load8(pc) | (load8(pc+1)<<8) | (load8(pc+2)<<16) | (load8(pc+3)<<24);
}

requires readable_bytes(x86_mov_rip,5);
requires load8(x86_mov_rip)==184;
requires readable_bytes(x86_mov_rip+1,4);
requires load8(x86_mov_rip+1)==((value>>0)&255);
requires load8(x86_mov_rip+2)==((value>>8)&255);
requires load8(x86_mov_rip+3)==((value>>16)&255);
requires load8(x86_mov_rip+4)==((value>>24)&255);
requires value>=0 && value<=4294967295;
modifies x86_mov_rip,x86_mov_rax;
ensures x86_mov_rip==old(x86_mov_rip)+5;
ensures x86_mov_rax==value;
ensures x86_mov_flags==old(x86_mov_flags) && x86_mov_rsp==old(x86_mov_rsp);
fn x86_model_mov_eax_imm32(value) {
    let pc=x86_mov_rip;
    x86_mov_rax=x86_read_mov_u32(pc+1);
    x86_mov_rip=pc+5;
}

requires readable_bytes(x86_mov_rip,7);
requires load8(x86_mov_rip)==72 && load8(x86_mov_rip+1)==199 && load8(x86_mov_rip+2)==192;
requires readable_bytes(x86_mov_rip+3,4);
requires load8(x86_mov_rip+3)==((value>>0)&255);
requires load8(x86_mov_rip+4)==((value>>8)&255);
requires load8(x86_mov_rip+5)==((value>>16)&255);
requires load8(x86_mov_rip+6)==((value>>24)&255);
requires value>=-2147483648 && value<0;
modifies x86_mov_rip,x86_mov_rax;
ensures x86_mov_rip==old(x86_mov_rip)+7;
ensures x86_mov_rax==value;
ensures x86_mov_flags==old(x86_mov_flags) && x86_mov_rsp==old(x86_mov_rsp);
fn x86_model_mov_rax_simm32(value) {
    let pc=x86_mov_rip;
    let bits=x86_read_mov_u32(pc+3);
    x86_mov_rax=(bits<<32)>>32;
    x86_mov_rip=pc+7;
}

requires readable_bytes(x86_mov_rip,10);
requires load8(x86_mov_rip)==72 && load8(x86_mov_rip+1)==184;
requires readable_bytes(x86_mov_rip+2,8);
requires load64(x86_mov_rip+2)==value;
modifies x86_mov_rip,x86_mov_rax;
ensures x86_mov_rip==old(x86_mov_rip)+10;
ensures x86_mov_rax==value;
ensures x86_mov_flags==old(x86_mov_flags) && x86_mov_rsp==old(x86_mov_rsp);
fn x86_model_mov_rax_imm64(value) {
    let pc=x86_mov_rip;
    x86_mov_rax=load64(pc+2);
    x86_mov_rip=pc+10;
}

requires readable_bytes(at,8);
requires load8(at+0)==((value>>0)&255);
requires load8(at+1)==((value>>8)&255);
requires load8(at+2)==((value>>16)&255);
requires load8(at+3)==((value>>24)&255);
requires load8(at+4)==((value>>32)&255);
requires load8(at+5)==((value>>40)&255);
requires load8(at+6)==((value>>48)&255);
requires load8(at+7)==((value>>56)&255);

ensures load64(at)==value;
lemma fn x86_mov_read_word(at,value) {}

requires writable_bytes(base,67108864);
requires start>=0 && start<=67108864-5;
ensures readable_bytes(base+start,5);
ensures readable_bytes(base+start+1,4);
lemma fn x86_mov_fetch_eax_u32(base,start) {}

requires output_limit==67108864;
requires output_size>=0 && output_size<=output_limit-5;
requires writable_bytes(output,67108864);
requires vm_mode==0;
requires value>=0 && value<=4294967295;
modifies output_size,native_address_site,native_boolean_end,bytes(output+output_size,5);
ensures output_size==old(output_size)+5;
ensures load8(output+old(output_size)+0)==184;
ensures load8(output+old(output_size)+1)==((value>>0)&255);
ensures load8(output+old(output_size)+2)==((value>>8)&255);
ensures load8(output+old(output_size)+3)==((value>>16)&255);
ensures load8(output+old(output_size)+4)==((value>>24)&255);
fn x86_emit_eax_u32(value) {
    ghost let origin=output_size;
PRODUCTION_EAX_U32_PREFIX
    proof {
        assert output_size==origin+1;
        assert output_size>=0 && output_size<=output_limit-4;
    }
PRODUCTION_EAX_U32_TAIL
}

requires output_limit==67108864;
requires output_size>=0 && output_size<=output_limit-5;
requires writable_bytes(output,67108864);
requires vm_mode==0;
requires value>=0 && value<=4294967295;
modifies output_size,native_address_site,native_boolean_end,x86_mov_rip,x86_mov_rax,bytes(output+output_size,5);
ensures x86_mov_rip==old(output+output_size)+5;
ensures x86_mov_rax==value;
ensures x86_mov_flags==old(x86_mov_flags) && x86_mov_rsp==old(x86_mov_rsp);
ensures output_size==old(output_size)+5;
fn x86_emit_and_model_eax_u32(value) {
    ghost let entered=output_size;
    let code=output+output_size;
    x86_emit_eax_u32(value);
    x86_mov_rip=code;
    proof {x86_mov_fetch_eax_u32(output,entered);}
    x86_model_mov_eax_imm32(value);
}

requires writable_bytes(base,67108864);
requires start>=0 && start<=67108864-7;
ensures readable_bytes(base+start,7);
ensures readable_bytes(base+start+3,4);
lemma fn x86_mov_fetch_rax_s32(base,start) {}

requires output_limit==67108864;
requires output_size>=0 && output_size<=output_limit-7;
requires writable_bytes(output,67108864);
requires vm_mode==0;
requires value>=-2147483648 && value<0;
modifies output_size,native_address_site,native_boolean_end,bytes(output+output_size,7);
ensures output_size==old(output_size)+7;
ensures load8(output+old(output_size)+0)==72;
ensures load8(output+old(output_size)+1)==199;
ensures load8(output+old(output_size)+2)==192;
ensures load8(output+old(output_size)+3)==((value>>0)&255);
ensures load8(output+old(output_size)+4)==((value>>8)&255);
ensures load8(output+old(output_size)+5)==((value>>16)&255);
ensures load8(output+old(output_size)+6)==((value>>24)&255);
fn x86_emit_rax_s32(value) {
    ghost let origin=output_size;
PRODUCTION_RAX_S32_PREFIX
    proof {
        assert output_size==origin+3;
        assert output_size>=0 && output_size<=output_limit-4;
    }
PRODUCTION_RAX_S32_TAIL
}

requires output_limit==67108864;
requires output_size>=0 && output_size<=output_limit-7;
requires writable_bytes(output,67108864);
requires vm_mode==0;
requires value>=-2147483648 && value<0;
modifies output_size,native_address_site,native_boolean_end,x86_mov_rip,x86_mov_rax,bytes(output+output_size,7);
ensures x86_mov_rip==old(output+output_size)+7;
ensures x86_mov_rax==value;
ensures x86_mov_flags==old(x86_mov_flags) && x86_mov_rsp==old(x86_mov_rsp);
ensures output_size==old(output_size)+7;
fn x86_emit_and_model_rax_s32(value) {
    ghost let entered=output_size;
    let code=output+output_size;
    x86_emit_rax_s32(value);
    x86_mov_rip=code;
    proof {x86_mov_fetch_rax_s32(output,entered);}
    x86_model_mov_rax_simm32(value);
}

requires writable_bytes(base,67108864);
requires start>=0 && start<=67108864-10;
ensures readable_bytes(base+start,10);
ensures readable_bytes(base+start+2,8);
lemma fn x86_mov_fetch_rax_u64(base,start) {}

requires output_limit==67108864;
requires output_size>=0 && output_size<=output_limit-10;
requires writable_bytes(output,67108864);
requires vm_mode==0;
requires value< -2147483648 || value>4294967295;
modifies output_size,native_address_site,native_boolean_end,bytes(output+output_size,10);
ensures output_size==old(output_size)+10;
ensures load8(output+old(output_size)+0)==72;
ensures load8(output+old(output_size)+1)==184;
ensures load8(output+old(output_size)+2)==((value>>0)&255);
ensures load8(output+old(output_size)+3)==((value>>8)&255);
ensures load8(output+old(output_size)+4)==((value>>16)&255);
ensures load8(output+old(output_size)+5)==((value>>24)&255);
ensures load8(output+old(output_size)+6)==((value>>32)&255);
ensures load8(output+old(output_size)+7)==((value>>40)&255);
ensures load8(output+old(output_size)+8)==((value>>48)&255);
ensures load8(output+old(output_size)+9)==((value>>56)&255);
fn x86_emit_rax_u64(value) {
    ghost let origin=output_size;
PRODUCTION_RAX_U64_PREFIX
    proof {
        assert output_size==origin+2;
        assert output_size>=0 && output_size<=output_limit-8;
    }
PRODUCTION_RAX_U64_TAIL
}

requires output_limit==67108864;
requires output_size>=0 && output_size<=output_limit-10;
requires writable_bytes(output,67108864);
requires vm_mode==0;
requires value< -2147483648 || value>4294967295;
modifies output_size,native_address_site,native_boolean_end,x86_mov_rip,x86_mov_rax,bytes(output+output_size,10);
ensures x86_mov_rip==old(output+output_size)+10;
ensures x86_mov_rax==value;
ensures x86_mov_flags==old(x86_mov_flags) && x86_mov_rsp==old(x86_mov_rsp);
ensures output_size==old(output_size)+10;
fn x86_emit_and_model_rax_u64(value) {
    ghost let entered=output_size;
    let code=output+output_size;
    x86_emit_rax_u64(value);
    x86_mov_rip=code;
    proof {
        x86_mov_fetch_rax_u64(output,entered);
        x86_mov_read_word(code+2,value);
    }
    x86_model_mov_rax_imm64(value);
}

requires writable_bytes(base,67108864);
requires cursor>=0 && cursor<67108864;
ensures writable_bytes(base+cursor,1);
lemma fn x86_mov_byte_grant(base,cursor) {}

requires output_limit==67108864;
requires output_size>=0 && output_size<=output_limit-10;
requires writable_bytes(output,67108864);
requires vm_mode==0;
modifies output_size,native_address_site,native_boolean_end,x86_mov_rip,x86_mov_rax,bytes(output+output_size,10);
ensures x86_mov_rip==output+output_size;
ensures x86_mov_rax==value;
ensures x86_mov_flags==old(x86_mov_flags) && x86_mov_rsp==old(x86_mov_rsp);
fn x86_emit_and_model_immediate(value) {
    ghost let entered=output_size;
    let code=output+output_size;
    if value>=0 && value<=4294967295 {
        x86_emit_and_model_eax_u32(value);
        proof {
            assert output_size==entered+5;
            assert x86_mov_rip==code+5;
            assert x86_mov_rip==output+output_size;
        }
        return 0;
    }else if value>=-2147483648 && value<0 {
        x86_emit_and_model_rax_s32(value);
        proof {
            assert output_size==entered+7;
            assert x86_mov_rip==code+7;
            assert x86_mov_rip==output+output_size;
        }
        return 0;
    }else {
        x86_emit_and_model_rax_u64(value);
        proof {
            assert output_size==entered+10;
            assert x86_mov_rip==code+10;
            assert x86_mov_rip==output+output_size;
        }
        return 0;
    }
}
