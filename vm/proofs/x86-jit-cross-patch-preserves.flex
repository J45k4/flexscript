// The selected offset load and native patch call come from the ordinary branch
// loop. The destination is supplied by the caller in this projection.
requires branch_count>=1 && branch_count<=8192 && error_count>=1 && error_count<=32768;
requires size>=6 && size<=67108864;
requires readable_bytes(branches,branch_count*16);
requires readable_bytes(errors,error_count*16);
requires watched_b>=0 && watched_b<branch_count && watched_e>=0 && watched_e<error_count;
requires readable_bytes(branches+watched_b*16,16);
requires readable_bytes(errors+watched_e*16,16);
requires load64(branches+watched_b*16)==branch_at;
requires load64(errors+watched_e*16)==error_at;
requires branch_at>=1 && branch_at<=size-4;
requires error_at>=2 && error_at<=size-4;

requires vm_mode==0;
requires target>=0 && target<size;
requires writable_bytes(output+branch_at,4);
requires writable_bytes(output+error_at,4);
modifies bytes(output+branch_at,4);
ensures result==0 || result==1;
ensures load8(output+error_at)==old(load8(output+error_at));
ensures load8(output+error_at+1)==old(load8(output+error_at+1));
ensures load8(output+error_at+2)==old(load8(output+error_at+2));
ensures load8(output+error_at+3)==old(load8(output+error_at+3));
fn jit_cross_guarded_branch_write(branches,errors,branch_count,error_count,size,target) {
    let record=branches+watched_b*16;
PRODUCTION_BRANCH_OFFSET
    proof {assert at==branch_at;}
    if !vm_jit_check_patch_order(branches,errors,branch_count,error_count,size) {return 0;}
    proof {
        jit_cross_either_patch_order(output,branch_at,error_at);
        jit_cross_write_span_alias(output,at,branch_at,error_at);
    }
PRODUCTION_BRANCH_PATCH
    return 1;
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

requires disjoint_bytes(right,4,left,4);
ensures disjoint_bytes(left,4,right,4);
lemma fn jit_cross_flip_spans(left,right) {}


requires at==branch;
requires branch>=1 && branch<=67108860;
requires writable_bytes(base+branch,4);
requires disjoint_bytes(base+branch,4,base+error,4);
ensures at>=0 && at<=67108860;
ensures writable_bytes(base+at,4);
ensures disjoint_bytes(base+at,4,base+error,4);
lemma fn jit_cross_write_span_alias(base,at,branch,error) {}
