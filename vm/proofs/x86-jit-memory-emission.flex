// Metered direct and indexed memory emission in the restricted x86-64 JIT.
// The gate inserts the production dispatch arms and the accepted VM address
// translator. This profile checks emission effects and map preservation.
requires vm_restricted!=0;
requires vm_heap_used>=16 && vm_heap_used<=1000000000;
requires vm_heap>0 && vm_heap<=0x7fffffffffffffff-vm_heap_used;
requires size==8;
modifies vm_error;
ensures (offset>=16 && offset<=vm_heap_used && size<=vm_heap_used-offset) || (result==0 && vm_error==3);
ensures offset<16 || offset>vm_heap_used || size>vm_heap_used-offset || (result==vm_heap+offset && vm_error==old(vm_error));
PRODUCTION_VM_ADDRESS

requires output_limit==67108864;
requires output_size>=0 && output_size<=output_limit-30;
requires writable_bytes(output,67108864);
requires vm_mode==0 && native_branch_mode==0;
requires vm_jit_error_count>=0 && vm_jit_error_count<32768;
requires writable_bytes(vm_jit_errors,524288);
requires disjoint_bytes(output,67108864,vm_jit_errors,524288);
requires vm_restricted!=0;
requires vm_heap_used>=16 && vm_heap_used<=1000000000;
requires vm_heap>0 && vm_heap<=0x7fffffffffffffff-vm_heap_used;
requires op==5 || op==6 || op==21 || op==22;
modifies vm_error,output_size,native_address_site,native_boolean_end,vm_jit_error_count,bytes(vm_jit_errors,524288),bytes(output,67108864);
ensures output_size>=old(output_size)+13 && output_size<=old(output_size)+30;
ensures (op!=5 && op!=6) || output_size==old(output_size)+13;
ensures op!=21 || output_size==old(output_size)+30;
ensures op!=22 || output_size==old(output_size)+28;
ensures vm_jit_error_count==old(vm_jit_error_count)+(op==21 || op==22);
ensures ((op==5 || op==6) && (arg<16 || arg>vm_heap_used-8)) || vm_error==old(vm_error);
fn jit_emit_memory_body(op,arg) {
    ghost let entered=output_size;
PRODUCTION_MEMORY_BODY
    proof {
        assert output_size>=entered+13;
        assert output_size<=entered+30;
    }
}

requires used>=16 && used<=1000000000;
requires arg>=16 && arg<=used-8;
ensures arg<=used;
ensures 8<=used-arg;
lemma fn jit_admits_heap_word(arg,used) {
    assert used-8>=0 && used-8<=used;
    assert arg+8<=used;
}

requires output_limit==67108864;
requires output_size>=0 && output_size<=output_limit-53;
requires writable_bytes(output,67108864);
requires vm_mode==0 && native_branch_mode==0;
requires vm_jit_error_count>=0 && vm_jit_error_count<=32766;
requires writable_bytes(vm_jit_errors,524288);
requires vm_restricted!=0;
requires vm_heap_used>=16 && vm_heap_used<=1000000000;
requires vm_heap>0 && vm_heap<=0x7fffffffffffffff-vm_heap_used;
requires op==5 || op==6 || op==21 || op==22;
requires readable_bytes(observed,8);
requires disjoint_bytes(output,67108864,vm_jit_errors,524288);
requires disjoint_bytes(output,67108864,observed,8);
requires disjoint_bytes(vm_jit_errors,524288,observed,8);
modifies vm_error,output_size,native_address_site,native_boolean_end,vm_jit_error_count,bytes(vm_jit_errors,524288),bytes(output,67108864);
ensures output_size>=old(output_size)+36 && output_size<=old(output_size)+53;
ensures vm_jit_error_count==old(vm_jit_error_count)+1+(op==21 || op==22);
ensures load64(observed)==old(load64(observed));
ensures ((op==5 || op==6) && (arg<16 || arg>vm_heap_used-8)) || vm_error==old(vm_error);
fn jit_emit_metered_memory_preserves_word(op,arg,observed) {
    ghost let value=load64(observed);
    vm_jit_meter();
    proof {assert load64(observed)==value;}
    jit_emit_memory_body(op,arg);
    proof {assert load64(observed)==value;}
}

requires output_limit==67108864;
requires output_size>=0 && output_size<=output_limit-53;
requires writable_bytes(output,67108864);
requires vm_mode==0 && native_branch_mode==0;
requires vm_jit_error_count>=0 && vm_jit_error_count<=32766;
requires writable_bytes(vm_jit_errors,524288);
requires vm_restricted!=0;
requires vm_heap_used>=16 && vm_heap_used<=1000000000;
requires vm_heap>0 && vm_heap<=0x7fffffffffffffff-vm_heap_used;
requires op==5 || op==6 || op==21 || op==22;
requires map_slot>=1 && map_slot<=8191;
requires watched>=1 && watched<=map_slot;
requires writable_bytes(vm_jit_map,8193*8);
requires writable_bytes(vm_jit_map+map_slot*8,8);
requires readable_bytes(vm_jit_map+watched*8,8);
requires disjoint_bytes(output,67108864,vm_jit_errors,524288);
requires disjoint_bytes(vm_jit_map,8193*8,output,67108864);
requires disjoint_bytes(vm_jit_map,8193*8,vm_jit_errors,524288);
modifies vm_error,output_size,native_address_site,native_boolean_end,vm_jit_error_count,bytes(vm_jit_errors,524288),bytes(output,67108864),bytes(vm_jit_map+map_slot*8,8);
ensures output_size>=old(output_size)+36 && output_size<=old(output_size)+53;
ensures vm_jit_error_count==old(vm_jit_error_count)+1+(op==21 || op==22);
ensures watched!=map_slot || load64(vm_jit_map+watched*8)==old(output_size);
ensures watched==map_slot || load64(vm_jit_map+watched*8)==old(load64(vm_jit_map+watched*8));
ensures ((op==5 || op==6) && (arg<16 || arg>vm_heap_used-8)) || vm_error==old(vm_error);
fn jit_record_map_and_emit_memory(op,arg,map_slot,watched) {
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
    jit_emit_metered_memory_preserves_word(op,arg,word);
    proof {assert load64(word)==stored;}
}
