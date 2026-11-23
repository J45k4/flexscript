// The gate inserts the ordinary branch loop. The watched globals occur only
// in annotations and describe the chosen table row and its mapped target.
global watched_row=0;
global watched_site=0;
global watched_index=0;
global watched_target=0;
global output=0;
global output_size=0;
global vm_mode=0;
global vm_jit_branches=0;
global vm_jit_branch_count=0;
global vm_jit_map=0;

requires vm_mode==0;
requires output_size>=0 && output_size<=67108864;
requires writable_bytes(output,output_size);
requires output>0 && output<=0x7fffffffffffffff-output_size;
requires vm_jit_branch_count<0 || vm_jit_branch_count>8192 || readable_bytes(vm_jit_branches,vm_jit_branch_count*16);
requires vm_jit_branch_count>=1 && vm_jit_branch_count<=8192;
requires watched_row>=0 && watched_row<vm_jit_branch_count;
requires watched_site>=1 && watched_site<=output_size-4;
requires writable_bytes(output+watched_site,4);
requires disjoint_bytes(output,output_size,vm_jit_branches+watched_row*16,16);
requires readable_bytes(vm_jit_branches+watched_row*16,16);
requires load64(vm_jit_branches+watched_row*16)==watched_site;
requires map_count>=1 && map_count<=8192;
requires readable_bytes(vm_jit_map,map_count*8);
requires watched_index>=1 && watched_index<map_count;
requires readable_bytes(vm_jit_map+watched_index*8,8);
requires disjoint_bytes(output,output_size,vm_jit_map+watched_index*8,8);
requires load64(vm_jit_branches+watched_row*16+8)==watched_index;
requires load64(vm_jit_map+watched_index*8)==watched_target;
modifies bytes(output,output_size);
ensures result==0 || (vm_jit_branch_count>=0 && vm_jit_branch_count<=8192);
ensures result==0 || load8(output+watched_site+0)==(((watched_target-watched_site-4)>>0)&255);
ensures result==0 || load8(output+watched_site+1)==(((watched_target-watched_site-4)>>8)&255);
ensures result==0 || load8(output+watched_site+2)==(((watched_target-watched_site-4)>>16)&255);
ensures result==0 || load8(output+watched_site+3)==(((watched_target-watched_site-4)>>24)&255);
ensures result==0 || result==1;
PRODUCTION_PROLOGUE
    ghost let want0=((watched_target-watched_site-4)>>0)&255;
    ghost let want1=((watched_target-watched_site-4)>>8)&255;
    ghost let want2=((watched_target-watched_site-4)>>16)&255;
    ghost let want3=((watched_target-watched_site-4)>>24)&255;
    invariant i>=0 && i<=vm_jit_branch_count;
    invariant patch_end>=0 && patch_end<=output_size;
    invariant i<=watched_row || patch_end>=watched_site+4;
    invariant load64(vm_jit_branches+watched_row*16)==watched_site;
    invariant load64(vm_jit_branches+watched_row*16+8)==watched_index;
    invariant load64(vm_jit_map+watched_index*8)==watched_target;
    invariant readable_bytes(vm_jit_map,map_count*8);
    invariant writable_bytes(output,output_size);
    invariant readable_bytes(vm_jit_branches,vm_jit_branch_count*16);
    // Evaluate each byte in the same heap at the head and after a step.
    // The Boolean operands are 0 or 1. Before the chosen row the bytes may differ.
    invariant (i<=watched_row) | (load8(output+watched_site+0)==want0);
    invariant (i<=watched_row) | (load8(output+watched_site+1)==want1);
    invariant (i<=watched_row) | (load8(output+watched_site+2)==want2);
    invariant (i<=watched_row) | (load8(output+watched_site+3)==want3);
    decreases vm_jit_branch_count-i;
PRODUCTION_LOOP_ENTRY

        proof {jit_branch_record_step(vm_jit_branches,i,vm_jit_branch_count);}
PRODUCTION_RECORD_READ
        proof {
            if i==watched_row {
                jit_error_record_alias(vm_jit_branches,i,watched_row);
                jit_branch_observed_record(record,vm_jit_branches+watched_row*16,at,index,watched_site,watched_index);
            }
            assert i!=watched_row || at==watched_site;
            assert i!=watched_row || index==watched_index;
        }
PRODUCTION_SITE_GUARD
        proof {
            jit_branch_map_slot(vm_jit_map,index,map_count);
            jit_error_selected_order(i,watched_row,patch_end,watched_site,at);
        }
PRODUCTION_TARGET
        proof {
            jit_branch_patch_span(output,output_size,at);
            jit_branch_separate_metadata(output,output_size,at,vm_jit_branches+watched_row*16,16);
            jit_branch_separate_metadata(output,output_size,at,vm_jit_map+watched_index*8,8);
            if i==watched_row {
                jit_branch_map_alias(vm_jit_map,index,watched_index);
                jit_branch_observed_target(vm_jit_map+index*8,vm_jit_map+watched_index*8,target,watched_target);
            }
            assert i!=watched_row || target==watched_target;
            if i>watched_row {
                assert at>=watched_site+4;
                jit_error_ordered_patches(output,watched_site,at);
            }
        }
        proof {jit_branch_patch_span(output,output_size,at);}
WATCHED_DISPLACEMENT_STEP
PRODUCTION_LOOP_END
    proof {jit_error_observed_exit(i,watched_row,vm_jit_branch_count);}
PRODUCTION_SUCCESS


PATCH_AND_BRANCH_LEMMAS

requires writable_bytes(base,size);
requires offset>=1 && offset<=size-4 && size<=67108864;
requires readable_bytes(record,length);
requires disjoint_bytes(base,size,record,length);
ensures disjoint_bytes(base+offset,4,record,length);
lemma fn jit_branch_separate_metadata(base,size,offset,record,length) {
    jit_branch_patch_span(base,size,offset);
}

requires index==watched;
ensures map+index*8==map+watched*8;
lemma fn jit_branch_map_alias(map,index,watched) {}

requires a==b;
requires readable_bytes(a,8);
requires readable_bytes(b,8);
requires load64(a)==target;
requires load64(b)==expected;
ensures target==expected;
lemma fn jit_branch_observed_target(a,b,target,expected) {}

ORDERED_PATCH_LEMMAS

requires i==row;
ensures table+i*16==table+row*16;
lemma fn jit_error_record_alias(table,i,row) {}

requires actual==expected;
requires readable_bytes(actual,16);
requires readable_bytes(expected,16);
requires load64(actual)==at && load64(actual+8)==index;
requires load64(expected)==site && load64(expected+8)==expected_index;
ensures at==site;
ensures index==expected_index;
lemma fn jit_branch_observed_record(actual,expected,at,index,site,expected_index) {
    assert actual+8==expected+8;
}

WATCHED_BYTE_LEMMAS

BRANCH_DECODE_PREMISES
requires watched_target>=0 && watched_target<output_size;
modifies bytes(output,output_size);
ensures result== -1 || result==watched_target;
fn jit_branch_relocate_and_decode(map_count) {
    if !vm_jit_patch_branches(map_count) {return -1;}
    let b0=load8(output+watched_site);
    let b1=load8(output+watched_site+1);
    let b2=load8(output+watched_site+2);
    let b3=load8(output+watched_site+3);
    let word=b0|(b1<<8)|(b2<<16)|(b3<<24);
    let relative=(word<<32)>>32;
    proof {
        jit_branch_relative_range(watched_site,watched_target,output_size);
        jit_branch_signed_bytes(watched_target-watched_site-4,b0,b1,b2,b3);
        assert relative==watched_target-watched_site-4;
        jit_branch_landing(watched_site,watched_target,relative,watched_target-watched_site-4);
    }
    return watched_site+4+relative;
}


requires relative==expected;
requires site+4+expected==target;
ensures site+4+relative==target;
lemma fn jit_branch_landing(site,target,relative,expected) {}
