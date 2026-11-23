// The selected byte comes from an error relocation recorded before ordinary patching.
global vm_jit_map=0;
global vm_jit_errors=0;
global output=0;
global vm_mode=0;
global watched_row=0;
global watched_site=0;
global watched_lane=0;

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
modifies bytes(output,size);
ensures result==0 || result==1;
ensures result==0 || load8(output+watched_site+watched_lane)==old(load8(output+watched_site+watched_lane));
PRODUCTION_ORDER_PROLOGUE
    ghost let watched_address=output+watched_site+watched_lane;
    ghost let watched_record=errors+watched_row*16;
    ghost let initial=load8(watched_address);
    invariant branch_row>=0 && branch_row<=branch_count;
    invariant error_row>=0 && error_row<=error_count;
    invariant frontier>=0 && frontier<=size;
    invariant error_row<=watched_row || frontier>=watched_site+4;
    invariant load64(watched_record)==watched_site;
    invariant (error_row<=watched_row && frontier>watched_site) | (load8(watched_address)==initial);
    decreases 9223372036854775807^frontier;
PRODUCTION_ORDER_LOOP
        proof {jit_cross_optional_row(branches,branch_row,branch_count);}
PRODUCTION_BRANCH_READ
        proof {jit_cross_optional_row(errors,error_row,error_count);}
PRODUCTION_ERROR_READ
        proof {
            if error_row==watched_row {
                jit_cross_address(errors,error_row,watched_row);
                jit_cross_load(errors+error_row*16,watched_record,error,watched_site);
            }
            assert error_row!=watched_row || error==watched_site;
            jit_cross_choice(branch_row,error_row,branch_count,error_count,branch,error,size);
        }
PRODUCTION_ORDER_CHOICE
        proof {
            jit_cross_bounds(branch_row,error_row,branch_count,error_count,frontier,site,size,branch,error,next_branch);
            jit_merged_error_step(error_row,watched_row,frontier,site,error,watched_site,next_branch);
        }
        ghost let needed=(error_row+(1-next_branch)>watched_row || site+4<=watched_site);
        ghost let saved=load8(watched_address);
        proof {
            jit_branch_patch_span(output,size,site);
            jit_merged_separate_record(output,size,site,watched_record);
            if needed {
                assert saved==initial;
                if next_branch {
                    jit_merged_patch_disjoint(output,site,watched_site);
                    jit_merged_lane_disjoint(output+site,output+watched_site,watched_address,watched_lane);
                }
            }
            assert !needed | (saved==initial);
            assert !next_branch || !needed || disjoint_bytes(output+site,4,watched_address,1);
        }
PRODUCTION_BRANCH_WRITE
        proof {
            assert load64(watched_record)==watched_site;
            if needed {
                assert load8(watched_address)==saved;
                jit_merged_transitive(load8(watched_address),saved,initial);
            }
            assert (error_row+(1-next_branch)<=watched_row && site+4>watched_site) | (load8(watched_address)==initial);
        }
PRODUCTION_ORDER_ADVANCE
    proof {jit_merged_exit(error_row,error_count,watched_row);}
PRODUCTION_ORDER_RETURN

requires e>=0 && e<=32768 && watched>=0 && watched<32768;
requires frontier>=0 && frontier<=site;
requires site>=1 && site<=67108860;
requires observed>=2 && observed<=67108860;
requires next==0 || next==1;
requires next!=0 || site==error;
requires e!=watched || error==observed;
requires e<=watched || frontier>=observed+4;
ensures e+(1-next)<=watched || site+4>=observed+4;
ensures (e+(1-next)<=watched && site+4>observed) || e>watched || frontier<=observed;
ensures next==0 || (e<=watched && site+4>observed) || site+4<=observed || observed+4<=site;
lemma fn jit_merged_error_step(e,watched,frontier,site,error,observed,next) {
    assert site+4>=site;
    if e>watched {
        assert frontier>=observed+4;
        assert site>=observed+4;
        assert site+4>=observed+4;
        return 0;
    }
    if next {
        assert next==1;
        if site+4<=observed {assert frontier<=observed;}
        return 0;
    }
    assert next==0;
    if e==watched {
        assert site==error && error==observed;
        assert frontier<=observed;
        return 0;
    }
    assert e+1<=watched;
    if site+4<=observed {assert frontier<=observed;}
}

requires e>=count && watched<count;
ensures e>watched;
lemma fn jit_merged_exit(e,count,watched) {}

requires base>0 && base<=9223372036854775807-size;
requires writable_bytes(base,size);
requires site>=1 && site<=size-4 && size<=67108864;
requires readable_bytes(record,16);
requires disjoint_bytes(base,size,record,16);
ensures disjoint_bytes(base+site,4,record,16);
lemma fn jit_merged_separate_record(base,size,site,record) {
    jit_branch_patch_span(base,size,site);
}

requires site>=1 && site<=67108860;
requires observed>=2 && observed<=67108860;
requires site+4<=observed || observed+4<=site;
requires writable_bytes(base+site,4);
requires writable_bytes(base+observed,4);
ensures disjoint_bytes(base+site,4,base+observed,4);
lemma fn jit_merged_patch_disjoint(base,site,observed) {
    jit_cross_either_patch_order(base,site,observed);
}

requires branch>=1 && branch<=67108860;
requires error>=2 && error<=67108860;
requires branch+4<=error || error+4<=branch;
requires writable_bytes(base+branch,4);
requires writable_bytes(base+error,4);
ensures disjoint_bytes(base+branch,4,base+error,4);
lemma fn jit_cross_either_patch_order(base,branch,error) {
    if branch+4<=error {
        jit_error_ordered_patches(base,branch,error);
        return 0;
    }
    jit_error_ordered_patches(base,error,branch);
    jit_cross_flip_spans(base+branch,base+error);
}

requires after==saved && saved==initial;
ensures after==initial;
lemma fn jit_merged_transitive(after,saved,initial) {}

requires next==0 || next==1;
requires site>=1 && site<=size-4 && size<=67108864 && vm_mode==0;
requires row>=0 && row<=8192;
requires next==0 || readable_bytes(branches+row*16,16);
requires map_count>=1 && map_count<=8192;
requires readable_bytes(vm_jit_map,map_count*8);
requires writable_bytes(output+site,4);
requires readable_bytes(vm_jit_errors+watched_row*16,16);
requires readable_bytes(output+watched_site+watched_lane,1);
requires disjoint_bytes(output+site,4,vm_jit_errors+watched_row*16,16);
modifies bytes(output+site,4);
ensures result==0 || result==1;
ensures load64(vm_jit_errors+watched_row*16)==old(load64(vm_jit_errors+watched_row*16));
ensures next!=0 || load8(output+watched_site+watched_lane)==old(load8(output+watched_site+watched_lane));
ensures !disjoint_bytes(output+site,4,output+watched_site+watched_lane,1) ||
    load8(output+watched_site+watched_lane)==old(load8(output+watched_site+watched_lane));
PRODUCTION_PATCH_PROLOGUE
    proof {jit_branch_map_slot(vm_jit_map,index,map_count);}
PRODUCTION_PATCH_TARGET
PRODUCTION_PATCH_STORE
PRODUCTION_PATCH_RETURN

ORDERED_SHARED_LEMMAS

ORDERED_OBSERVATION_LEMMAS

PRODUCTION_PATCH32
