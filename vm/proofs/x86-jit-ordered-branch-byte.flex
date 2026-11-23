// Observe all four bytes of the selected ordinary branch displacement.
global vm_jit_map=0;
global vm_jit_errors=0;
global output=0;
global vm_mode=0;
global watched_row=0;
global watched_site=0;
global watched_index=0;
global watched_target=0;
global watched_bits=0;

requires vm_mode==0;
requires branch_count>=1 && branch_count<=8192 && error_count>=0 && error_count<=32768;
requires map_count>=1 && map_count<=8192;
requires readable_bytes(vm_jit_map,map_count*8);
requires size>=5 && size<=67108864;
requires output>0 && output<=9223372036854775807-size;
requires writable_bytes(output,size);
requires readable_bytes(branches,branch_count*16);
requires readable_bytes(vm_jit_errors,error_count*16);
requires watched_row>=0 && watched_row<branch_count;
requires watched_site>=1 && watched_site<=size-4;
requires watched_bits==((watched_target-watched_site-4)&4294967295);
requires watched_index>=1 && watched_index<map_count;
requires watched_target>=0 && watched_target<size;
requires readable_bytes(branches+watched_row*16,16);
requires readable_bytes(vm_jit_map+watched_index*8,8);
requires disjoint_bytes(output,size,branches+watched_row*16,16);
requires disjoint_bytes(output,size,vm_jit_map+watched_index*8,8);
requires load64(branches+watched_row*16)==watched_site;
requires load64(branches+watched_row*16+8)==watched_index;
requires load64(vm_jit_map+watched_index*8)==watched_target;
requires writable_bytes(output+watched_site,4);
modifies bytes(output,size);
ensures result==0 || result==1;
ensures result==0 || jit_rel32_bits(output+watched_site)==watched_bits;
PRODUCTION_ORDER_PROLOGUE
    ghost let watched_address=output+watched_site;
    ghost let watched_record=branches+watched_row*16;
    ghost let watched_map=vm_jit_map+watched_index*8;
    ghost let want=watched_bits;
    invariant branch_row>=0 && branch_row<=branch_count;
    invariant error_row>=0 && error_row<=error_count;
    invariant frontier>=0 && frontier<=size;
    invariant branch_row<=watched_row || frontier>=watched_site+4;
    invariant load64(watched_record)==watched_site;
    invariant load64(watched_record+8)==watched_index;
    invariant load64(watched_map)==watched_target;
    invariant (branch_row<=watched_row) | (jit_rel32_bits(watched_address)==want);
    decreases 9223372036854775807^frontier;
PRODUCTION_ORDER_LOOP
        proof {jit_cross_optional_row(branches,branch_row,branch_count);}
PRODUCTION_BRANCH_READ
        proof {jit_cross_optional_row(errors,error_row,error_count);}
PRODUCTION_ERROR_READ
        proof {
            if branch_row==watched_row {
                jit_cross_address(branches,branch_row,watched_row);
                jit_cross_load(branches+branch_row*16,watched_record,branch,watched_site);
            }
            assert branch_row!=watched_row || branch==watched_site;
            jit_cross_choice(branch_row,error_row,branch_count,error_count,branch,error,size);
        }
PRODUCTION_ORDER_CHOICE
        proof {
            jit_cross_bounds(branch_row,error_row,branch_count,error_count,frontier,site,size,branch,error,next_branch);
            jit_merged_branch_step(branch_row,watched_row,frontier,site,branch,watched_site,next_branch);
            jit_branch_patch_span(output,size,site);
            jit_merged_separate_metadata(output,size,site,watched_record,16);
            jit_merged_separate_metadata(output,size,site,watched_map,8);
            if next_branch && branch_row>watched_row {
                jit_error_ordered_patches(output,watched_site,site);
                jit_cross_flip_spans(output+site,output+watched_site);
            }
            assert !next_branch || branch_row<=watched_row || disjoint_bytes(output+site,4,watched_address,4);
        }
        ghost let saved=jit_rel32_bits(watched_address);
PRODUCTION_BRANCH_WRITE
        ghost let current=jit_rel32_bits(watched_address);
        proof {
            if branch_row>watched_row {
                assert saved==want;
                assert current==saved;
            }
            if branch_row==watched_row && next_branch {
                assert branch_row==watched_row;
                assert next_branch==1;
                assert current==want;
            }
            jit_merged_branch_value_step(branch_row,watched_row,next_branch,saved,current,want);
        }
PRODUCTION_ORDER_ADVANCE
    proof {jit_merged_branch_exit(branch_row,branch_count,watched_row);}
PRODUCTION_ORDER_RETURN

requires b>=0 && b<=8192 && watched>=0 && watched<8192;
requires frontier>=0 && frontier<=site;
requires site>=1 && site<=67108860;
requires observed>=1 && observed<=67108860;
requires next==0 || next==1;
requires next==0 || site==branch;
requires b!=watched || branch==observed;
requires b<=watched || frontier>=observed+4;
ensures b+next<=watched || site+4>=observed+4;
ensures next==0 || b!=watched || site==observed;
ensures b<=watched || site>=observed+4;
ensures b>=watched || b+next<=watched;
lemma fn jit_merged_branch_step(b,watched,frontier,site,branch,observed,next) {
    assert site+4>=site;
    if b>watched {
        assert site>=observed+4;
        return 0;
    }
    if b<watched {
        assert b+1<=watched;
        return 0;
    }
    if next {
        assert next==1;
        assert site==branch && branch==observed;
    }
}

requires b>=count && watched<count;
ensures b>watched;
lemma fn jit_merged_branch_exit(b,count,watched) {}

requires base>0 && base<=9223372036854775807-size;
requires writable_bytes(base,size);
requires site>=1 && site<=size-4 && size<=67108864;
requires readable_bytes(record,length);
requires disjoint_bytes(base,size,record,length);
ensures disjoint_bytes(base+site,4,record,length);
lemma fn jit_merged_separate_metadata(base,size,site,record,length) {
    jit_branch_patch_span(base,size,site);
}

requires next==0 || next==1;
requires site>=1 && site<=size-4 && size<=67108864 && vm_mode==0;
requires row>=0 && row<=8192;
requires next==0 || readable_bytes(branches+row*16,16);
requires map_count>=1 && map_count<=8192;
requires readable_bytes(vm_jit_map,map_count*8);
requires writable_bytes(output+site,4);
requires writable_bytes(output+watched_site,4);
requires watched_bits==((watched_target-watched_site-4)&4294967295);
requires readable_bytes(branches+watched_row*16,16);
requires readable_bytes(vm_jit_map+watched_index*8,8);
requires load64(branches+watched_row*16+8)==watched_index;
requires load64(vm_jit_map+watched_index*8)==watched_target;
requires disjoint_bytes(output+site,4,branches+watched_row*16,16);
requires disjoint_bytes(output+site,4,vm_jit_map+watched_index*8,8);
requires next==0 || row!=watched_row || site==watched_site;
modifies bytes(output+site,4);
ensures result==0 || result==1;
ensures load64(branches+watched_row*16)==old(load64(branches+watched_row*16));
ensures load64(branches+watched_row*16+8)==old(load64(branches+watched_row*16+8));
ensures load64(vm_jit_map+watched_index*8)==watched_target;
ensures next!=0 || jit_rel32_bits(output+watched_site)==old(jit_rel32_bits(output+watched_site));
ensures !disjoint_bytes(output+site,4,output+watched_site,4) ||
    jit_rel32_bits(output+watched_site)==old(jit_rel32_bits(output+watched_site));
ensures (result!=1 || next==0 || row!=watched_row) |
    (jit_rel32_bits(output+watched_site)==watched_bits);
PRODUCTION_PATCH_PROLOGUE
    proof {
        jit_branch_map_slot(vm_jit_map,index,map_count);
        if row==watched_row {
            jit_cross_address(branches,row,watched_row);
            jit_merged_branch_index_value(record,branches+watched_row*16,index,watched_index);
        }
        assert row!=watched_row || index==watched_index;
    }
PRODUCTION_PATCH_TARGET
    proof {
        if row==watched_row {
            assert index==watched_index;
            jit_merged_branch_map_alias(vm_jit_map,index,watched_index);
            jit_merged_branch_target_value(vm_jit_map+index*8,vm_jit_map+watched_index*8,target,watched_target);
            assert site==watched_site;
            jit_merged_same_branch_word(site,watched_site,target,watched_target);
        }
        assert row!=watched_row || target-site-4==watched_target-watched_site-4;
    }
PRODUCTION_PATCH_STORE
    proof {
        if row==watched_row {
            assert site==watched_site;
            jit_rel32_written_bits(output+site,target-site-4);
            jit_rel32_same_address(output+site,output+watched_site);
            jit_rel32_expected_bits(target-site-4,watched_target-watched_site-4,
                jit_rel32_bits(output+watched_site),watched_bits);
        }
    }
PRODUCTION_PATCH_RETURN

requires after==before && before==want;
ensures after==want;
lemma fn jit_error_observed_value_transitive(after,before,want) {}
requires b>=0 && b<=8192 && watched>=0 && watched<8192;
requires next==0 || next==1;
requires b<=watched || saved==want;
requires b<=watched || current==saved;
requires b!=watched || next==0 || current==want;
ensures (b+next<=watched) | (current==want);
lemma fn jit_merged_branch_value_step(b,watched,next,saved,current,want) {
    if b>watched {
        assert current==want;
        return 0;
    }
    if b<watched {
        assert b+next<=watched;
    }
}

requires actual==expected;
requires readable_bytes(actual,16) && readable_bytes(expected,16);
requires load64(actual+8)==index && load64(expected+8)==wanted;
ensures index==wanted;
lemma fn jit_merged_branch_index_value(actual,expected,index,wanted) {
    assert actual+8==expected+8;
}

requires index==wanted;
ensures map+index*8==map+wanted*8;
lemma fn jit_merged_branch_map_alias(map,index,wanted) {}

requires actual==expected;
requires readable_bytes(actual,8) && readable_bytes(expected,8);
requires load64(actual)==target && load64(expected)==wanted;
ensures target==wanted;
lemma fn jit_merged_branch_target_value(actual,expected,target,wanted) {}

requires site==expected_site && target==expected_target;
ensures target-site-4==expected_target-expected_site-4;
lemma fn jit_merged_same_branch_word(site,expected_site,target,expected_target) {}

ORDERED_SHARED_LEMMAS

ORDERED_OBSERVATION_LEMMAS

PRODUCTION_PATCH32

requires size>=5 && size<=67108864;
requires site>=1 && site<=size-4;
requires target>=0 && target<size;
ensures target-site-4>=-67108864 && target-site-4<=67108864;
ensures site+4+(target-site-4)==target;
lemma fn jit_branch_relative_range(site,target,size) {
    assert site+4>=5 && site+4<=size;
    assert target<=67108863;
}

requires value>=-67108864 && value<=67108864;
requires b0==(value&255);
requires b1==((value>>8)&255);
requires b2==((value>>16)&255);
requires b3==((value>>24)&255);
ensures (((b0|(b1<<8)|(b2<<16)|(b3<<24))<<32)>>32)==value;
lemma fn jit_branch_signed_bytes(value,b0,b1,b2,b3) {
    let decoded=b0|(b1<<8)|(b2<<16)|(b3<<24);
    assert decoded==(value&4294967295);
    assert (decoded<<32)==(value<<32);
    assert (value<<32)>>32==value;
}

requires size>=5 && size<=67108864;
requires site>=1 && site<=size-4;
requires target>=0 && target<size;
requires b0==((target-site-4)&255);
requires b1==(((target-site-4)>>8)&255);
requires b2==(((target-site-4)>>16)&255);
requires b3==(((target-site-4)>>24)&255);
requires relative==(((b0|(b1<<8)|(b2<<16)|(b3<<24))<<32)>>32);
ensures site+4+relative==target;
lemma fn jit_merged_decode_branch(site,target,size,b0,b1,b2,b3,relative) {
    jit_branch_relative_range(site,target,size);
    jit_branch_signed_bytes(target-site-4,b0,b1,b2,b3);
    jit_merged_branch_landing(site,target,relative,target-site-4);
}

requires relative==expected;
requires site+4+expected==target;
ensures site+4+relative==target;
lemma fn jit_merged_branch_landing(site,target,relative,expected) {}

requires readable_bytes(at,4);
spec fn jit_rel32_bits(at) {
    return load8(at)|(load8(at+1)<<8)|(load8(at+2)<<16)|(load8(at+3)<<24);
}

requires readable_bytes(at,4);
requires load8(at)==(value&255);
requires load8(at+1)==((value>>8)&255);
requires load8(at+2)==((value>>16)&255);
requires load8(at+3)==((value>>24)&255);
ensures jit_rel32_bits(at)==(value&4294967295);
lemma fn jit_rel32_written_bits(at,value) {}

requires at==watched;
requires readable_bytes(at,4);
requires readable_bytes(watched,4);
ensures jit_rel32_bits(at)==jit_rel32_bits(watched);
lemma fn jit_rel32_same_address(at,watched) {}

requires actual==expected;
requires bits==(actual&4294967295);
requires watched==(expected&4294967295);
ensures bits==watched;
lemma fn jit_rel32_expected_bits(actual,expected,bits,watched) {}
