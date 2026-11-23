// Production x86-64 scratch admission, emitter limit, and function prologue.
// The proof gate inserts the current scratch, emitter, and prologue source.
// The full-buffer diagnostic is modeled as a rejection before the byte store.
global output=0;
global output_limit=67108864;
global output_size=0;
global vm_mode=0;
global native_address_site=0;
global native_boolean_end=0;
global vm_jit_context_slot=0;
global vm_jit_branch_count=0;
global vm_jit_error_count=0;

PRODUCTION_JIT_SCRATCH_PROFILE

requires writable_bytes(vm_jit_buffer,67108864);
modifies output,output_size,output_limit,vm_mode;
ensures result==old(output_limit);
ensures output==vm_jit_buffer && output_size==0 && output_limit==67108864 && vm_mode==0;
ensures writable_bytes(output,67108864);
PRODUCTION_BEGIN_STAGING

modifies output_limit;
ensures output_limit==bytecode_limit;
ensures output==old(output) && output_size==old(output_size) && vm_mode==old(vm_mode);
fn jit_restore_emission_limit(bytecode_limit) {
PRODUCTION_RESTORE_LIMIT
}

requires vm_jit_buffer==0;
modifies vm_jit_buffer,vm_jit_map,vm_jit_branches,vm_jit_errors,output,output_size,output_limit,vm_mode;
ensures result==0 || result==1;
ensures result==0 || (output==vm_jit_buffer && output_size==0 && output_limit==67108864 && vm_mode==0);
ensures result==0 || writable_bytes(output,67108864);
ensures result==0 || disjoint_bytes(output,67108864,vm_jit_map,8193*8);
ensures result==0 || disjoint_bytes(output,67108864,vm_jit_branches,8192*16);
ensures result==0 || disjoint_bytes(output,67108864,vm_jit_errors,8192*64);
ensures result!=0 || (output==old(output) && output_size==old(output_size) && output_limit==old(output_limit) && vm_mode==old(vm_mode));
fn jit_allocate_and_begin_staging() {
    if !jit_allocate_scratch_view() {return 0;}
    vm_jit_begin_staging();
    return 1;
}

requires writable_bytes(base,67108864);
requires cursor>=0 && cursor<67108864;
ensures writable_bytes(base+cursor,1);
lemma fn jit_staging_byte_grant(base,cursor) {}

requires output_limit==67108864;
requires output_size>=0 && output_size<67108864;
requires writable_bytes(output,67108864);
modifies output_size,native_address_site,native_boolean_end,bytes(output,67108864);
ensures result==0 && output_size==old(output_size)+1;
PRODUCTION_EMIT_BYTE

requires output_limit==67108864 && output_size==67108864;
modifies native_address_site,native_boolean_end;
ensures result==-1;
PRODUCTION_EMIT_GUARD

requires output_limit==67108864;
requires output_size>=0 && output_size<=output_limit-4;
requires writable_bytes(output,67108864);
modifies output_size,native_address_site,native_boolean_end,bytes(output,67108864);
ensures output_size==old(output_size)+4;
PRODUCTION_EMIT_WORD

requires output_limit==67108864;
requires output_size>=0 && output_size<=output_limit-7;
requires writable_bytes(output,67108864);
requires slot>=0 && slot<4096;
modifies output_size,native_address_site,native_boolean_end,bytes(output,67108864);
ensures output_size==old(output_size)+7;
PRODUCTION_EMIT_LOCAL

requires i>=0 && i<slots && slots<=4096;
ensures i<4096;
ensures 21+14*i>=0 && 21+14*i<=67108864-14;
ensures 21+14*(i+1)==21+14*i+14;
ensures i+1<=slots && slots-(i+1)>=0 && slots-(i+1)<slots-i;
lemma fn jit_prologue_iteration(i,slots) {
    assert i<=4095;
    assert 14*i<=57330;
    assert 14*(i+1)==14*i+14;
}

requires slots>=0 && slots<=4096;
requires writable_bytes(vm_jit_buffer,67108864);
modifies output,output_size,output_limit,vm_mode,vm_jit_context_slot,vm_jit_branch_count,vm_jit_error_count,native_address_site,native_boolean_end,bytes(vm_jit_buffer,67108864);
ensures result==old(output_limit);
ensures output==vm_jit_buffer && output_limit==67108864 && vm_mode==0;
ensures writable_bytes(output,67108864);
ensures vm_jit_context_slot==-8*(slots+1);
ensures vm_jit_branch_count==0 && vm_jit_error_count==0;
ensures output_size==21+14*slots;
ensures output_size>=21 && output_size<=57365;
fn jit_begin_and_emit_prologue(slots) {
    let bytecode_limit=vm_jit_begin_staging();
PRODUCTION_PROLOGUE_SETUP
PRODUCTION_PROLOGUE
    proof {
        assert i==slots;
        assert 14*slots<=57344;
    }
    return bytecode_limit;
}

requires vm_jit_buffer==0;
requires slots>=0 && slots<=4096;
modifies vm_jit_buffer,vm_jit_map,vm_jit_branches,vm_jit_errors,output,output_size,output_limit,vm_mode,vm_jit_context_slot,vm_jit_branch_count,vm_jit_error_count,native_address_site,native_boolean_end;
ensures result==0 || result==1;
ensures result==0 || (output==vm_jit_buffer && output_limit==67108864 && vm_mode==0);
ensures result==0 || output_size==21+14*slots;
ensures result==0 || (output_size>=21 && output_size<=57365);
ensures result==0 || (vm_jit_branch_count==0 && vm_jit_error_count==0);
ensures result==0 || writable_bytes(output,67108864);
ensures result==0 || fresh_bytes(output,67108864);
ensures result==0 || disjoint_bytes(output,67108864,vm_jit_map,8193*8);
ensures result==0 || disjoint_bytes(output,67108864,vm_jit_branches,8192*16);
ensures result==0 || disjoint_bytes(output,67108864,vm_jit_errors,8192*64);
ensures result!=0 || (output==old(output) && output_size==old(output_size) && output_limit==old(output_limit) && vm_mode==old(vm_mode));
fn jit_allocate_and_emit_prologue(slots) {
    if !jit_allocate_scratch_view() {return 0;}
    jit_begin_and_emit_prologue(slots);
    return 1;
}

// Staging and the prologue leave an admitted instruction readable and unchanged.
requires slots>=0 && slots<=4096;
requires bytecode_size>=16 && bytecode_size<=268435456;
requires pc>=0 && pc<=bytecode_size-16;
requires output==bytecode && output_size==bytecode_size;
requires writable_bytes(vm_jit_buffer,67108864);
requires readable_bytes(bytecode,bytecode_size);
requires disjoint_bytes(vm_jit_buffer,67108864,bytecode,bytecode_size);
modifies output,output_size,output_limit,vm_mode,vm_jit_context_slot,vm_jit_branch_count,vm_jit_error_count,native_address_site,native_boolean_end,bytes(vm_jit_buffer,67108864);
ensures output==vm_jit_buffer && output_limit==67108864 && vm_mode==0;
ensures output_size>=21 && output_size<=57365;
ensures vm_jit_branch_count==0 && vm_jit_error_count==0;
ensures readable_bytes(bytecode,bytecode_size);
ensures load64(bytecode+pc)==old(load64(bytecode+pc));
ensures load64(bytecode+pc+8)==old(load64(bytecode+pc+8));
fn jit_stage_keeps_selected_bytecode(bytecode,bytecode_size,pc,slots) {
    proof {jit_prologue_code_words(vm_jit_buffer,bytecode,bytecode_size,pc);}
    ghost let op=load64(bytecode+pc);
    ghost let arg=load64(bytecode+pc+8);
    jit_begin_and_emit_prologue(slots);
    proof {
        assert load64(bytecode+pc)==op;
        assert load64(bytecode+pc+8)==arg;
    }
}

requires size>=16 && size<=268435456;
requires pc>=0 && pc<=size-16;
requires readable_bytes(code,size);
requires disjoint_bytes(staging,67108864,code,size);
ensures readable_bytes(code+pc,8);
ensures readable_bytes(code+pc+8,8);
ensures disjoint_bytes(staging,67108864,code+pc,16);
lemma fn jit_prologue_code_words(staging,code,size,pc) {
    assert readable_bytes(code+pc,16);
    jit_granted_instruction_words(code+pc);
}

requires readable_bytes(pair,16);
ensures readable_bytes(pair,8);
ensures readable_bytes(pair+8,8);
lemma fn jit_granted_instruction_words(pair) {}
