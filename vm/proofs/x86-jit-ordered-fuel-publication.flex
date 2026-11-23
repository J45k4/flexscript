// Composes the selected fuel relocation, ordered ordinary pass, and
// publication with the mapping and protection outcomes supplied.
global vm_jit_error_count=0;
global output_size=0;
global vm_jit_cache=0;
global vm_jit_bytes=0;
global vm_jit_compilations=0;

ORDERED_BRANCH_PROFILE

PUBLICATION_PROFILE

requires vm_mode==0;
requires branch_count>=0 && branch_count<=8192 && error_count>=1 && error_count<=32768;
requires map_count>=1 && map_count<=8192;
requires readable_bytes(vm_jit_map,map_count*8);
requires size>=6 && size<=67108864;
requires output>0 && output<=9223372036854775807-size;
requires writable_bytes(output,size);
requires readable_bytes(branches,branch_count*16);
requires readable_bytes(vm_jit_errors,error_count*16);
requires disjoint_bytes(output,size,branches,branch_count*16);
requires disjoint_bytes(output,size,vm_jit_errors,error_count*16);
requires watched_row>=0 && watched_row<error_count;
requires watched_site>=2 && watched_site<=size-4;
requires watched_lane>=0 && watched_lane<4;
requires readable_bytes(vm_jit_errors+watched_row*16,16);
requires disjoint_bytes(output,size,vm_jit_errors+watched_row*16,16);
requires load64(vm_jit_errors+watched_row*16)==watched_site;
requires writable_bytes(output+watched_site,4);
requires readable_bytes(output+watched_site+watched_lane,1);
requires output_size>=1 && output_size<=1048576;
requires observed>=0 && observed<output_size;
requires vm_jit_bytes>=0 && vm_jit_bytes<=16777216;
requires vm_jit_bytes+((output_size+4095)/4096)*4096<=16777216;
requires index>=0 && index<18432;
requires mapped>0 && mapped<=9223372036854775807-output_size+1;
requires readable_bytes(output,output_size);
requires readable_bytes(output+observed,1);
requires writable_bytes(mapped,output_size);
requires disjoint_bytes(output,output_size,mapped,output_size);
requires writable_bytes(vm_jit_cache+index*32,16);
requires readable_bytes(vm_jit_cache+index*32+16,16);
requires disjoint_bytes(vm_jit_cache+index*32,16,vm_jit_cache+index*32+16,16);
requires disjoint_bytes(mapped,output_size,vm_jit_cache+index*32,16);
requires disjoint_bytes(mapped,output_size,vm_jit_cache+index*32+16,16);
requires disjoint_bytes(mapped+observed,1,vm_jit_cache+index*32,16);

requires size==output_size;
requires observed==watched_site+watched_lane;
requires output+observed==output+watched_site+watched_lane;
modifies output,output_size,vm_mode,vm_jit_bytes,vm_jit_compilations,bytes(output,size),bytes(mapped,output_size),bytes(vm_jit_cache+index*32,16);
ensures result==0 || load8(mapped+observed)==old(load8(output+observed));
ensures output==bytecode && output_size==bytecode_size && vm_mode==1;
ensures result==0 || result==mapped && protection>=0;
ensures result==0 || load64(vm_jit_cache+index*32)==mapped;
fn jit_merged_patch_and_publish(branches,branch_count,error_count,size,map_count,index,bytecode,bytecode_size,mapped,protection,observed) {
    ghost let expected=load8(output+observed);
    let patched=vm_jit_patch_branches(branches,branch_count,error_count,size,map_count);
    if patched {
        proof {
            jit_cross_publication_byte_alias(output+observed,output+watched_site+watched_lane);
            assert readable_bytes(output+observed,1);
            assert load8(output+observed)==expected;
        }
        return vm_jit_publish_admitted_image(index,bytecode,bytecode_size,mapped,protection,observed);
    }
    output=bytecode;output_size=bytecode_size;vm_mode=1;
    return 0;
}

requires address==source;
requires readable_bytes(source,1);
ensures readable_bytes(address,1);
ensures load8(address)==load8(source);
lemma fn jit_cross_publication_byte_alias(address,source) {}

FUEL_RELOCATION_PROFILE

requires lane>=0 && lane<4;
requires readable_bytes(base+site,4);
requires readable_bytes(base+(site+lane),1);
requires load8(base+site+0)==((value>>0)&255);
requires load8(base+site+1)==((value>>8)&255);
requires load8(base+site+2)==((value>>16)&255);
requires load8(base+site+3)==((value>>24)&255);
ensures load8(base+(site+lane))==((value>>(lane*8))&255);
lemma fn jit_fuel_selected_lane(base,site,lane,value) {
    if lane==0 {
        assert lane==0;
        assert base+(site+lane)==base+site+0;
        return 0;
    }
    if lane==1 {
        assert lane==1;
        assert base+(site+lane)==base+site+1;
        return 0;
    }
    if lane==2 {
        assert lane==2;
        assert base+(site+lane)==base+site+2;
        return 0;
    }
    assert lane==3;
    assert base+(site+lane)==base+site+3;
}
requires vm_mode==0;
requires branch_count>=0 && branch_count<=8192 && error_count>=1 && error_count<=32768;
requires map_count>=1 && map_count<=8192;
requires readable_bytes(vm_jit_map,map_count*8);
requires size>=6 && size<=67108864;
requires output>0 && output<=9223372036854775807-size;
requires writable_bytes(output,size);
requires readable_bytes(branches,branch_count*16);
requires readable_bytes(vm_jit_errors,error_count*16);
requires disjoint_bytes(output,size,branches,branch_count*16);
requires disjoint_bytes(output,size,vm_jit_errors,error_count*16);
requires watched_row>=0 && watched_row<error_count;
requires watched_site>=2 && watched_site<=size-4;
requires watched_lane>=0 && watched_lane<4;
requires readable_bytes(vm_jit_errors+watched_row*16,16);
requires disjoint_bytes(output,size,vm_jit_errors+watched_row*16,16);
requires load64(vm_jit_errors+watched_row*16)==watched_site;
requires writable_bytes(output+watched_site,4);
requires readable_bytes(output+watched_site+watched_lane,1);
requires output_size>=1 && output_size<=1048576;
requires observed>=0 && observed<output_size;
requires vm_jit_bytes>=0 && vm_jit_bytes<=16777216;
requires vm_jit_bytes+((output_size+4095)/4096)*4096<=16777216;
requires index>=0 && index<18432;
requires mapped>0 && mapped<=9223372036854775807-output_size+1;
requires readable_bytes(output,output_size);
requires readable_bytes(output+observed,1);
requires writable_bytes(mapped,output_size);
requires disjoint_bytes(output,output_size,mapped,output_size);
requires writable_bytes(vm_jit_cache+index*32,16);
requires readable_bytes(vm_jit_cache+index*32+16,16);
requires disjoint_bytes(vm_jit_cache+index*32,16,vm_jit_cache+index*32+16,16);
requires disjoint_bytes(mapped,output_size,vm_jit_cache+index*32,16);
requires disjoint_bytes(mapped,output_size,vm_jit_cache+index*32+16,16);
requires disjoint_bytes(mapped+observed,1,vm_jit_cache+index*32,16);

requires size==output_size;
requires observed==watched_site+watched_lane;
requires output+observed==output+watched_site+watched_lane;

requires error_count==vm_jit_error_count;
requires output+observed==output+(watched_site+watched_lane);
requires readable_bytes(output+(watched_site+watched_lane),1);
requires vm_jit_error_count>=1 && vm_jit_error_count<=32768;
requires readable_bytes(vm_jit_errors,vm_jit_error_count*16);
requires watched_row<vm_jit_error_count;
requires watched_site<=output_size-4;
requires output>0 && output<=0x7fffffffffffffff-output_size;
requires writable_bytes(output,output_size);
requires load64(vm_jit_errors+watched_row*16+8)==1;
modifies output,output_size,vm_mode,vm_jit_bytes,vm_jit_compilations,bytes(output,size),bytes(mapped,output_size),bytes(vm_jit_cache+index*32,16);
ensures output==bytecode && output_size==bytecode_size && vm_mode==1;
ensures result==0 || result==mapped && protection>=0;
ensures result==0 || load64(vm_jit_cache+index*32)==mapped;
ensures result==0 || load8(mapped+observed)==(((fuel-watched_site-4)>>(watched_lane*8))&255);
fn jit_relocate_fuel_merge_and_publish(branches,branch_count,error_count,size,map_count,index,bytecode,bytecode_size,mapped,protection,observed,failure,fuel,division,bounds,timeout) {
    if vm_jit_patch_errors(failure,fuel,division,bounds,timeout) {
        proof {
            jit_fuel_selected_lane(output,watched_site,watched_lane,fuel-watched_site-4);
            jit_cross_publication_byte_alias(output+observed,output+(watched_site+watched_lane));
            assert load8(output+observed)==(((fuel-watched_site-4)>>(watched_lane*8))&255);
        }
        return jit_merged_patch_and_publish(branches,branch_count,error_count,size,map_count,index,bytecode,bytecode_size,mapped,protection,observed);
    }
    output=bytecode;output_size=bytecode_size;vm_mode=1;
    return 0;
}
