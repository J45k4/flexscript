// Production x86-64 meter and local access emission. The proof gate specializes
// the unused overflow diagnostics and non-JIT jump modes, then adds annotations.
// The watcher may be any readable word disjoint from staging and the error table.
global output=0;
global output_size=0;
global output_limit=67108864;
global native_address_site=0;
global native_boolean_end=0;
global vm_mode=0;
global native_branch_mode=0;
global vm_jit_errors=0;
global vm_jit_error_count=0;
global vm_jit_context_slot=0;
global vm_jit_map=0;

requires output_limit==67108864;
requires output_size>=0 && output_size<=output_limit-1;
requires writable_bytes(output,67108864);
modifies output_size,native_address_site,native_boolean_end,bytes(output,67108864);
ensures output_size==old(output_size)+1;
ensures result==0;
PRODUCTION_EMIT

requires output_limit==67108864;
requires output_size>=0 && output_size<=output_limit-4;
requires writable_bytes(output,67108864);
modifies output_size,native_address_site,native_boolean_end,bytes(output,67108864);
ensures output_size==old(output_size)+4;
ensures result==0;
PRODUCTION_EMIT32

requires output_limit==67108864;
requires output_size>=0 && output_size<=output_limit-6;
requires writable_bytes(output,67108864);
requires vm_mode==0 && native_branch_mode==0;
requires opcode==132;
modifies output_size,native_address_site,native_boolean_end,bytes(output,67108864);
ensures output_size==old(output_size)+6;
ensures result==old(output_size)+2;
PRODUCTION_JUMP

requires output_limit==67108864;
requires output_size>=0 && output_size<=output_limit-6;
requires writable_bytes(output,67108864);
requires vm_mode==0 && native_branch_mode==0;
requires vm_jit_error_count>=0 && vm_jit_error_count<32768;
requires writable_bytes(vm_jit_errors,524288);
requires op==132;
requires disjoint_bytes(output,67108864,vm_jit_errors,524288);
modifies output_size,native_address_site,native_boolean_end,vm_jit_error_count,bytes(vm_jit_errors,524288),bytes(output,67108864);
ensures output_size==old(output_size)+6;
ensures vm_jit_error_count==old(vm_jit_error_count)+1;
PRODUCTION_VM_JIT_ERROR_JUMP

requires output_limit==67108864;
requires output_size>=0 && output_size<=output_limit-7;
requires writable_bytes(output,67108864);
modifies output_size,native_address_site,native_boolean_end,bytes(output,67108864);
ensures output_size==old(output_size)+7;
ensures result==0;
PRODUCTION_VM_JIT_LOAD_CONTEXT

requires output_limit==67108864;
requires output_size>=0 && output_size<=output_limit-23;
requires writable_bytes(output,67108864);
requires vm_mode==0 && native_branch_mode==0;
requires vm_jit_error_count>=0 && vm_jit_error_count<32768;
requires writable_bytes(vm_jit_errors,524288);
requires disjoint_bytes(output,67108864,vm_jit_errors,524288);
modifies output_size,native_address_site,native_boolean_end,vm_jit_error_count,bytes(vm_jit_errors,524288),bytes(output,67108864);
ensures output_size==old(output_size)+23;
ensures vm_jit_error_count==old(vm_jit_error_count)+1;
ensures result==0;
PRODUCTION_VM_JIT_METER

requires output_limit==67108864;
requires output_size>=0 && output_size<=output_limit-7;
requires writable_bytes(output,67108864);
modifies output_size,native_address_site,native_boolean_end,bytes(output,67108864);
ensures output_size==old(output_size)+7;
ensures result==0;
PRODUCTION_VM_JIT_LOCAL

requires output_limit==67108864;
requires output_size>=0 && output_size<=output_limit-30;
requires writable_bytes(output,67108864);
requires vm_mode==0 && native_branch_mode==0;
requires vm_jit_error_count>=0 && vm_jit_error_count<32768;
requires writable_bytes(vm_jit_errors,524288);
requires op==3 || op==4;
requires slot>=0 && slot<4096;
requires readable_bytes(observed,8);
requires disjoint_bytes(output,67108864,vm_jit_errors,524288);
requires disjoint_bytes(output,67108864,observed,8);
requires disjoint_bytes(vm_jit_errors,524288,observed,8);
modifies output_size,native_address_site,native_boolean_end,vm_jit_error_count,bytes(vm_jit_errors,524288),bytes(output,67108864);
ensures output_size==old(output_size)+30;
ensures vm_jit_error_count==old(vm_jit_error_count)+1;
ensures load64(observed)==old(load64(observed));
ensures result==0;
fn jit_emit_metered_local_preserves_word(op,slot,observed) {
    ghost let value=load64(observed);
    vm_jit_meter();
    proof {assert load64(observed)==value;}
    vm_jit_local(slot,op==4);
    proof {assert load64(observed)==value;}
    return 0;
}

requires writable_bytes(base,67108864);
requires cursor>=0 && cursor<67108864;
ensures writable_bytes(base+cursor,1);
lemma fn jit_staging_byte_grant(base,cursor) {}

requires output_limit==67108864;
requires output_size>=0 && output_size<=output_limit-30;
requires writable_bytes(output,67108864);
requires vm_mode==0 && native_branch_mode==0;
requires vm_jit_error_count>=0 && vm_jit_error_count<32768;
requires writable_bytes(vm_jit_errors,524288);
requires op==3 || op==4;
requires slot>=0 && slot<4096;
requires map_slot>=1 && map_slot<=8191;
requires watched>=1 && watched<=map_slot;
requires writable_bytes(vm_jit_map,8193*8);
requires writable_bytes(vm_jit_map+map_slot*8,8);
requires readable_bytes(vm_jit_map+watched*8,8);
requires disjoint_bytes(output,67108864,vm_jit_errors,524288);
requires disjoint_bytes(vm_jit_map,8193*8,output,67108864);
requires disjoint_bytes(vm_jit_map,8193*8,vm_jit_errors,524288);
modifies output_size,native_address_site,native_boolean_end,vm_jit_error_count,bytes(vm_jit_errors,524288),bytes(output,67108864),bytes(vm_jit_map+map_slot*8,8);
ensures output_size==old(output_size)+30;
ensures vm_jit_error_count==old(vm_jit_error_count)+1;
ensures watched!=map_slot || load64(vm_jit_map+watched*8)==old(output_size);
ensures watched==map_slot || load64(vm_jit_map+watched*8)==old(load64(vm_jit_map+watched*8));
fn jit_record_map_and_emit_local(op,slot,map_slot,watched) {
    ghost let before=output_size;
    let word=vm_jit_map+watched*8;
    ghost let previous=load64(word);
    proof {
        jit_emit_map_observer(vm_jit_map,watched,output,vm_jit_errors);
        if watched==map_slot {jit_record_map_alias(vm_jit_map,map_slot,watched);}
        else {jit_record_map_ordered_words(vm_jit_map,watched,map_slot);}
    }
PRODUCTION_MAP_STORE
    ghost let stored=load64(word);
    proof {
        assert watched!=map_slot || stored==before;
        assert watched==map_slot || stored==previous;
    }
    jit_emit_metered_local_preserves_word(op,slot,word);
    proof {assert load64(word)==stored;}
}

requires watched>=1 && watched<=8191;
requires writable_bytes(map,8193*8);
requires disjoint_bytes(map,8193*8,staging,67108864);
requires disjoint_bytes(map,8193*8,errors,524288);
ensures disjoint_bytes(staging,67108864,map+watched*8,8);
ensures disjoint_bytes(errors,524288,map+watched*8,8);
lemma fn jit_emit_map_observer(map,watched,staging,errors) {
    assert watched*8>=8 && watched*8<=8191*8;
}
