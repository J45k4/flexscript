// Connect the emitted row and map values to both production relocation
// passes. The watched globals carry observations in this proof projection.
global output_size=0;
global vm_jit_branches=0;
global vm_jit_branch_count=0;
global vm_jit_error_count=0;

ORDERED_BRANCH_PROFILE

ERROR_RELOCATION_PROFILE

TARGET_INDEX_PROFILE

requires vm_mode==0;
requires start>=0 && start<=268435440 && start%16==0;
requires map_count>=2 && map_count<=8192;
requires end==start+map_count*16 && end<=268435456;
requires (op==10 || op==11 || op==12) && arg>=start+16 && arg<end && arg%16==0;
requires target_index>=1 && target_index<map_count && target_index==(arg-start)/16;
requires vm_jit_branch_count>=1 && vm_jit_branch_count<=8192;
requires vm_jit_error_count>=0 && vm_jit_error_count<=32768;
requires row>=0 && row<vm_jit_branch_count;
requires output_size>=5 && output_size<=67108864;
requires output>0 && output<=0x7fffffffffffffff-output_size;
requires site>=1 && site<=output_size-4;
requires native_target>=0 && native_target<output_size;
requires writable_bytes(output,output_size);
requires readable_bytes(vm_jit_branches,vm_jit_branch_count*16);
requires readable_bytes(vm_jit_errors,vm_jit_error_count*16);
requires readable_bytes(vm_jit_map,map_count*8);
requires readable_bytes(vm_jit_branches+row*16,16);
requires readable_bytes(vm_jit_map+target_index*8,8);
requires disjoint_bytes(output,output_size,vm_jit_branches+row*16,16);
requires disjoint_bytes(output,output_size,vm_jit_map+target_index*8,8);
requires load64(vm_jit_branches+row*16)==site;
requires load64(vm_jit_branches+row*16+8)==target_index;
requires load64(vm_jit_map+target_index*8)==native_target;
modifies watched_row,watched_site,watched_index,watched_target,watched_bits,bytes(output,output_size);
ensures result==0 || result==1;
ensures watched_index==target_index;
ensures watched_site==site;
ensures watched_target==native_target;
ensures result==0 || (site+4+((jit_rel32_bits(output+site)<<32)>>32)==native_target);
ensures result==0 || jit_rel32_bits(output+site)==((native_target-site-4)&4294967295);
fn jit_relocate_selected_branch(start,end,map_count,op,arg,target_index,row,site,native_target,failure,fuel,division,bounds,timeout) {
    let index=jit_relocation_target_index(start,end,map_count,op,arg);
    proof {
        assert index==target_index;
        jit_branch_patch_span(output,output_size,site);
    }
    let record=vm_jit_branches+row*16;
    watched_row=row;
    watched_site=site;
    watched_index=target_index;
    watched_target=native_target;
    watched_bits=(watched_target-watched_site-4)&4294967295;
    proof {
        assert watched_site==site && watched_index==target_index && watched_target==native_target;
    }
PRODUCTION_ORDINARY_ERROR_PASS
    proof {
        assert load64(record)==site;
        assert load64(record+8)==target_index;
        assert load64(vm_jit_map+target_index*8)==native_target;
        assert writable_bytes(output+site,4);
    }
PRODUCTION_ORDINARY_BRANCH_PASS
        return 0;
    }
    proof {
        jit_rel32_target_landing(site,native_target,output_size,jit_rel32_bits(output+site));
    }
    return 1;
}

requires size>=5 && size<=67108864;
requires site>=1 && site<=size-4;
requires target>=0 && target<size;
requires encoded==((target-site-4)&4294967295);
ensures site+4+((encoded<<32)>>32)==target;
lemma fn jit_rel32_target_landing(site,target,size,encoded) {
    jit_branch_relative_range(site,target,size);
    let delta=target-site-4;
    assert (encoded<<32)==(delta<<32);
    let relative=(encoded<<32)>>32;
    assert relative==delta;
    jit_merged_branch_landing(site,target,relative,delta);
}
