// Additional metered opcode bodies for the production emitter projection.
// The VM gate inserts the relevant dispatch arms and compiler emitters into
// this profile and checks it together with x86-jit-local-emission.flex.
requires output_limit==67108864;
requires output_size>=0 && output_size<=output_limit-8;
requires writable_bytes(output,67108864);
modifies output_size,native_address_site,native_boolean_end,bytes(output,67108864);
ensures output_size==old(output_size)+8;
ensures result==0;
PRODUCTION_EMIT64

requires output_limit==67108864;
requires output_size>=0 && output_size<=output_limit-10;
requires writable_bytes(output,67108864);
requires vm_mode==0;
modifies output_size,native_address_site,native_boolean_end,bytes(output,67108864);
ensures output_size==old(output_size)+5+2*(n>=-2147483648 && n<0)+5*(n< -2147483648 || n>4294967295);
ensures output_size>=old(output_size)+5 && output_size<=old(output_size)+10;
ensures result==0;
PRODUCTION_IMMEDIATE

requires output_limit==67108864;
requires output_size>=0 && output_size<=output_limit-3;
requires writable_bytes(output,67108864);
requires vm_mode==0;
modifies output_size,native_address_site,native_boolean_end,bytes(output,67108864);
ensures output_size==old(output_size)+3;
ensures result==0;
PRODUCTION_TEST_RAX

requires output_limit==67108864;
requires output_size>=0 && output_size<=output_limit-10;
requires writable_bytes(output,67108864);
requires vm_mode==0;
requires op==1 || op==2 || op==14 || op==15 || op==16;
modifies output_size,native_address_site,native_boolean_end,bytes(output,67108864);
ensures op!=1 || output_size==old(output_size)+5+
    2*(arg>=-2147483648 && arg<0)+5*(arg< -2147483648 || arg>4294967295);
ensures op!=2 || output_size==old(output_size)+1;
ensures (op!=14 && op!=16) || output_size==old(output_size)+3;
ensures op!=15 || output_size==old(output_size)+10;
ensures output_size>=old(output_size)+1 && output_size<=old(output_size)+10;
fn jit_emit_simple_body(op,arg) {
    ghost let entered=output_size;
PRODUCTION_SIMPLE_BODY
    proof {
        assert op!=1 || output_size>=entered+1;
        assert op!=1 || output_size<=entered+10;
        assert output_size>=entered+1;
        assert output_size<=entered+10;
    }
}

requires output_limit==67108864;
requires output_size>=0 && output_size<=output_limit-33;
requires writable_bytes(output,67108864);
requires vm_mode==0 && native_branch_mode==0;
requires vm_jit_error_count>=0 && vm_jit_error_count<32768;
requires writable_bytes(vm_jit_errors,524288);
requires op==1 || op==2 || op==14 || op==15 || op==16;
requires readable_bytes(observed,8);
requires disjoint_bytes(output,67108864,vm_jit_errors,524288);
requires disjoint_bytes(output,67108864,observed,8);
requires disjoint_bytes(vm_jit_errors,524288,observed,8);
modifies output_size,native_address_site,native_boolean_end,vm_jit_error_count,bytes(vm_jit_errors,524288),bytes(output,67108864);
ensures output_size>=old(output_size)+24 && output_size<=old(output_size)+33;
ensures vm_jit_error_count==old(vm_jit_error_count)+1;
ensures load64(observed)==old(load64(observed));
fn jit_emit_metered_simple_preserves_word(op,arg,observed) {
    ghost let value=load64(observed);
    vm_jit_meter();
    proof {assert load64(observed)==value;}
    jit_emit_simple_body(op,arg);
    proof {assert load64(observed)==value;}
}

requires output_limit==67108864;
requires output_size>=0 && output_size<=output_limit-33;
requires writable_bytes(output,67108864);
requires vm_mode==0 && native_branch_mode==0;
requires vm_jit_error_count>=0 && vm_jit_error_count<32768;
requires writable_bytes(vm_jit_errors,524288);
requires op==1 || op==2 || op==14 || op==15 || op==16;
requires map_slot>=1 && map_slot<=8191;
requires watched>=1 && watched<=map_slot;
requires writable_bytes(vm_jit_map,8193*8);
requires writable_bytes(vm_jit_map+map_slot*8,8);
requires readable_bytes(vm_jit_map+watched*8,8);
requires disjoint_bytes(output,67108864,vm_jit_errors,524288);
requires disjoint_bytes(vm_jit_map,8193*8,output,67108864);
requires disjoint_bytes(vm_jit_map,8193*8,vm_jit_errors,524288);
modifies output_size,native_address_site,native_boolean_end,vm_jit_error_count,bytes(vm_jit_errors,524288),bytes(output,67108864),bytes(vm_jit_map+map_slot*8,8);
ensures output_size>=old(output_size)+24 && output_size<=old(output_size)+33;
ensures vm_jit_error_count==old(vm_jit_error_count)+1;
ensures watched!=map_slot || load64(vm_jit_map+watched*8)==old(output_size);
ensures watched==map_slot || load64(vm_jit_map+watched*8)==old(load64(vm_jit_map+watched*8));
fn jit_record_map_and_emit_simple(op,arg,map_slot,watched) {
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
    jit_emit_metered_simple_preserves_word(op,arg,word);
    proof {assert load64(word)==stored;}
}
