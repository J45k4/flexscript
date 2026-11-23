// The gate inserts the production loop and native writer profiles. The two
// observation globals occur only in annotations. A successful loop supplies
// the exact fuel displacement for any selected kind-1 record.
global watched_row=0;
global watched_site=0;
global output=0;
global output_size=0;
global vm_mode=0;
global vm_jit_errors=0;
global vm_jit_error_count=0;

requires vm_mode==0;
requires output_size>=0 && output_size<=67108864;
requires writable_bytes(output,output_size);
requires output>0 && output<=0x7fffffffffffffff-output_size;
requires vm_jit_error_count<0 || vm_jit_error_count>32768 || readable_bytes(vm_jit_errors,vm_jit_error_count*16);
requires vm_jit_error_count>=1 && vm_jit_error_count<=32768;
requires watched_row>=0 && watched_row<vm_jit_error_count;
requires watched_site>=2 && watched_site<=output_size-4;
requires writable_bytes(output+watched_site,4);
requires disjoint_bytes(output,output_size,vm_jit_errors+watched_row*16,16);
requires readable_bytes(vm_jit_errors+watched_row*16,16);
requires load64(vm_jit_errors+watched_row*16)==watched_site;
requires load64(vm_jit_errors+watched_row*16+8)==1;
modifies bytes(output,output_size);
ensures result==0 || (vm_jit_error_count>=0 && vm_jit_error_count<=32768);
ensures result==0 || load8(output+watched_site+0)==(((fuel-watched_site-4)>>0)&255);
ensures result==0 || load8(output+watched_site+1)==(((fuel-watched_site-4)>>8)&255);
ensures result==0 || load8(output+watched_site+2)==(((fuel-watched_site-4)>>16)&255);
ensures result==0 || load8(output+watched_site+3)==(((fuel-watched_site-4)>>24)&255);
ensures result==0 || result==1;
PRODUCTION_PROLOGUE
    ghost let want0=((fuel-watched_site-4)>>0)&255;
    ghost let want1=((fuel-watched_site-4)>>8)&255;
    ghost let want2=((fuel-watched_site-4)>>16)&255;
    ghost let want3=((fuel-watched_site-4)>>24)&255;
    invariant i>=0 && i<=vm_jit_error_count;
    invariant patch_end>=0 && patch_end<=output_size;
    invariant i<=watched_row || patch_end>=watched_site+4;
    invariant load64(vm_jit_errors+watched_row*16)==watched_site;
    invariant load64(vm_jit_errors+watched_row*16+8)==1;
    invariant writable_bytes(output,output_size);
    invariant readable_bytes(vm_jit_errors,vm_jit_error_count*16);
    // Evaluate each byte in the same heap at the head and after a step.
    // The Boolean operands are 0 or 1. Before the chosen row the bytes may differ.
    invariant (i<=watched_row) | (load8(output+watched_site+0)==want0);
    invariant (i<=watched_row) | (load8(output+watched_site+1)==want1);
    invariant (i<=watched_row) | (load8(output+watched_site+2)==want2);
    invariant (i<=watched_row) | (load8(output+watched_site+3)==want3);
    decreases vm_jit_error_count-i;
PRODUCTION_LOOP_ENTRY
        proof {jit_error_row_step(vm_jit_errors,i,vm_jit_error_count);}
PRODUCTION_RECORD_READ
        proof {
            if i==watched_row {
                jit_error_record_alias(vm_jit_errors,i,watched_row);
                jit_error_observed_record(record,vm_jit_errors+watched_row*16,at,kind,watched_site);
            }
            assert i!=watched_row || at==watched_site;
            assert i!=watched_row || kind==1;
        }
PRODUCTION_SELECT_AND_GUARD
        proof {
            jit_error_patch_span(output,output_size,at);
            jit_error_patch_separate_from_observed_record(output,output_size,at,vm_jit_errors+watched_row*16);
            assert i!=watched_row || target==fuel;
            jit_error_selected_order(i,watched_row,patch_end,watched_site,at);
            if i>watched_row {
                assert at>=watched_site+4;
                jit_error_ordered_patches(output,watched_site,at);
            }
        }
        proof {jit_error_patch_span(output,output_size,at);}
        ghost let before0=load8(output+watched_site+0);
        ghost let before1=load8(output+watched_site+1);
        ghost let before2=load8(output+watched_site+2);
        ghost let before3=load8(output+watched_site+3);
PRODUCTION_WRITE
        ghost let current0=load8(output+watched_site+0);
        ghost let current1=load8(output+watched_site+1);
        ghost let current2=load8(output+watched_site+2);
        ghost let current3=load8(output+watched_site+3);
        proof {
            if i<watched_row {
                jit_error_step_before(i,watched_row);
                assert (i+1<=watched_row) | (current0==want0);
                assert (i+1<=watched_row) | (current1==want1);
                assert (i+1<=watched_row) | (current2==want2);
                assert (i+1<=watched_row) | (current3==want3);
            } else {
                if i==watched_row {
                    assert at==watched_site && target==fuel;
                    jit_error_same_displacement(at,watched_site,target,fuel);
                    jit_error_same_address_at_lane(output,at,watched_site,0);
                    jit_error_alias_byte_value(output+at+0,output+watched_site+0,((target-at-4)>>0)&255,want0);
                    assert current0==want0;
                    jit_error_same_address_at_lane(output,at,watched_site,1);
                    jit_error_alias_byte_value(output+at+1,output+watched_site+1,((target-at-4)>>8)&255,want1);
                    assert current1==want1;
                    jit_error_same_address_at_lane(output,at,watched_site,2);
                    jit_error_alias_byte_value(output+at+2,output+watched_site+2,((target-at-4)>>16)&255,want2);
                    assert current2==want2;
                    jit_error_same_address_at_lane(output,at,watched_site,3);
                    jit_error_alias_byte_value(output+at+3,output+watched_site+3,((target-at-4)>>24)&255,want3);
                    assert current3==want3;
                } else {
                    assert disjoint_bytes(output+watched_site,4,output+at,4);
                    assert before0==want0;
                    assert before1==want1;
                    assert before2==want2;
                    assert before3==want3;
                    assert current0==before0;
                    assert current1==before1;
                    assert current2==before2;
                    assert current3==before3;
                    jit_error_observed_value_transitive(current0,before0,want0);
                    jit_error_observed_value_transitive(current1,before1,want1);
                    jit_error_observed_value_transitive(current2,before2,want2);
                    jit_error_observed_value_transitive(current3,before3,want3);
                }
                assert (i+1<=watched_row) | (current0==want0);
                assert (i+1<=watched_row) | (current1==want1);
                assert (i+1<=watched_row) | (current2==want2);
                assert (i+1<=watched_row) | (current3==want3);
            }
        }
PRODUCTION_LOOP_END
    proof {jit_error_observed_exit(i,watched_row,vm_jit_error_count);}
PRODUCTION_SUCCESS

PATCH_AND_LOOP_LEMMAS

requires writable_bytes(base,size);
requires offset>=2 && offset<=size-4 && size<=67108864;
requires base>0 && base<=0x7fffffffffffffff-size;
requires readable_bytes(record,16);
requires disjoint_bytes(base,size,record,16);
ensures disjoint_bytes(base+offset,4,record,16);
lemma fn jit_error_patch_separate_from_observed_record(base,size,offset,record) {
    jit_error_patch_span(base,size,offset);
}

ORDERED_PATCH_LEMMAS

requires i==row;
ensures table+i*16==table+row*16;
lemma fn jit_error_record_alias(table,i,row) {}

requires actual==expected;
requires readable_bytes(actual,16);
requires readable_bytes(expected,16);
requires load64(actual)==at && load64(actual+8)==kind;
requires load64(expected)==site && load64(expected+8)==1;
ensures at==site;
ensures kind==1;
lemma fn jit_error_observed_record(actual,expected,at,kind,site) {
    assert actual+8==expected+8;
}

requires i>=0 && i<32768 && row>=0 && row<32768;
requires patch_end>=0 && patch_end<=67108864;
requires site>=2 && site<=67108860;
requires at>=2 && at<=67108860 && at>=patch_end;
requires i<=row || patch_end>=site+4;
requires i!=row || at==site;
ensures i<=row || at>=site+4;
ensures i+1<=row || at+4>=site+4;
lemma fn jit_error_selected_order(i,row,patch_end,site,at) {
    if i<row {
        assert i+1<=row;
        return 0;
    }
    if i==row {
        assert at==site;
        return 0;
    }
    assert patch_end>=site+4;
    assert at>=site+4;
    assert at+4>=site+4;
}

requires address==observed;
requires written==want;
requires readable_bytes(address,1);
requires readable_bytes(observed,1);
requires load8(address)==written;
ensures load8(observed)==want;
lemma fn jit_error_alias_byte_value(address,observed,written,want) {}

requires !(i<count);
requires row<count;
ensures i>row;
lemma fn jit_error_observed_exit(i,row,count) {}

requires at==site && target==fuel;
ensures target-at-4==fuel-site-4;
lemma fn jit_error_same_displacement(at,site,target,fuel) {}

requires i>=0 && i<row && row<32768;
ensures i+1<=row;
lemma fn jit_error_step_before(i,row) {}

requires at==site;
ensures (base+at)+lane==(base+site)+lane;
lemma fn jit_error_same_address_at_lane(base,at,site,lane) {}

requires after==before && before==want;
ensures after==want;
lemma fn jit_error_observed_value_transitive(after,before,want) {}
