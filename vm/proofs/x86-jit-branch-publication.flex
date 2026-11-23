// Carry a self-target displacement from the production emission and
// relocation projections into the modeled allocation and publication path.
requires bytecode_size>=16 && bytecode_size<=268435456;
requires start>=0 && start<=268435440 && start%16==0;
requires count>=2 && count<=8192;
requires observed>=1 && observed<count;
requires end==start+count*16 && end<=bytecode_size;
requires slots>=0 && slots<=4096;
requires output_size>=21 && output_size<=57365;
requires vm_jit_error_count==0 && vm_jit_branch_count==0;
requires output_limit==67108864;
requires vm_mode==0 && native_branch_mode==0;
requires !native_register_frame || !native_reg_replay;
requires vm_restricted!=0;
requires vm_heap_used>=16 && vm_heap_used<=1000000000;
requires vm_heap>0 && vm_heap<=0x7fffffffffffffff-vm_heap_used;
requires readable_bytes(bytecode,bytecode_size);
requires writable_bytes(output,67108864);
requires writable_bytes(vm_jit_errors,524288);
requires writable_bytes(vm_jit_branches,8192*16);
requires writable_bytes(vm_jit_map,8193*8);
requires disjoint_bytes(output,67108864,vm_jit_errors,524288);
requires disjoint_bytes(output,67108864,vm_jit_branches,8192*16);
requires disjoint_bytes(vm_jit_errors,524288,vm_jit_branches,8192*16);
requires disjoint_bytes(output,67108864,vm_jit_map,8193*8);
requires disjoint_bytes(vm_jit_errors,524288,vm_jit_map,8193*8);
requires disjoint_bytes(vm_jit_branches,8192*16,vm_jit_map,8193*8);
requires disjoint_bytes(output,67108864,bytecode,bytecode_size);
requires disjoint_bytes(vm_jit_errors,524288,bytecode,bytecode_size);
requires disjoint_bytes(vm_jit_branches,8192*16,bytecode,bytecode_size);
requires disjoint_bytes(vm_jit_map,8193*8,bytecode,bytecode_size);
requires pc==start+observed*16 && pc%16==0;
requires readable_bytes(bytecode+pc,8);
requires readable_bytes(bytecode+pc+8,8);
requires load64(bytecode+pc)>=10 && load64(bytecode+pc)<=12;
requires load64(bytecode+pc+8)==pc;
requires output>0 && output<=0x7fffffffffffffff-67108864;
requires index>=0 && index<18432;
requires vm_jit_bytes>=0 && vm_jit_bytes<=16777216;
requires writable_bytes(vm_jit_cache+index*32,16);
requires readable_bytes(vm_jit_cache+index*32,32);
requires disjoint_bytes(vm_jit_cache+index*32,16,vm_jit_cache+index*32+16,16);
requires disjoint_bytes(output,67108864,vm_jit_cache+index*32,32);
requires disjoint_bytes(vm_jit_errors,524288,vm_jit_cache+index*32,32);
requires disjoint_bytes(vm_jit_branches,8192*16,vm_jit_cache+index*32,32);
requires disjoint_bytes(vm_jit_map,8193*8,vm_jit_cache+index*32,32);
modifies vm_error,output,output_size,output_limit,vm_mode,vm_jit_bytes,vm_jit_compilations,native_address_site,native_address_kind,native_address_value,native_binary_cached,native_boolean_end,native_boolean_start,native_boolean_cc,vm_jit_error_count,vm_jit_branch_count,watched_row,watched_site,watched_index,watched_target,watched_bits,bytes(vm_jit_errors,524288),bytes(vm_jit_branches,8192*16),bytes(output,67108864),bytes(vm_jit_map,8193*8),bytes(vm_jit_cache+index*32,16);
ensures output==bytecode && output_size==bytecode_size && vm_mode==1;
ensures output_limit==bytecode_limit;
ensures result==0 || result>0 && protection>=0;
ensures result==0 || watched_index==observed;
ensures result==0 || load64(vm_jit_cache+index*32)==result;
ensures result==0 || readable_bytes(result+watched_site,4);
ensures result==0 || result+watched_site+4+((jit_rel32_bits(result+watched_site)<<32)>>32)==result+watched_target;
fn jit_emit_relocate_and_publish_self_branch(bytecode,bytecode_size,start,end,slots,count,observed,pc,index,bytecode_limit,protection) {
    let relocated=jit_emit_and_relocate_self_branch(bytecode,bytecode_size,start,end,slots,count,observed,pc,bytecode_limit);
    if relocated {
        let site=watched_site;
        let target=watched_target;
        proof {
            jit_branch_patch_span(output,output_size,site);
            assert readable_bytes(output+site,4);
            jit_decoded_staged_branch_delta(site,target,output_size,jit_rel32_bits(output+site));
        }
        return jit_allocate_and_publish_displacement(index,bytecode,bytecode_size,protection,site,target);
    }
PRODUCTION_RELOCATION_FALLBACK_RESTORE
    return 0;
}

requires size>=5 && size<=67108864;
requires site>=1 && site<=size-4;
requires target>=0 && target<size;
requires bits==((target-site-4)&4294967295);
ensures ((bits<<32)>>32)==target-site-4;
lemma fn jit_decoded_staged_branch_delta(site,target,size,bits) {
    jit_branch_relative_range(site,target,size);
    let delta=target-site-4;
    assert (bits<<32)==(delta<<32);
    assert ((delta<<32)>>32)==delta;
}
