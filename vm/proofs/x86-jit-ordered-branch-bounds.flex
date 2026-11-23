// Bounds and termination for the production merged ordinary branch pass.
global output=0;
global vm_mode=0;
global vm_jit_map=0;
global vm_jit_errors=0;

requires vm_mode==0;
requires size>=0 && size<=67108864;
requires writable_bytes(output,size);
requires branch_count<0 || branch_count>8192 || readable_bytes(branches,branch_count*16);
requires error_count<0 || error_count>32768 || readable_bytes(vm_jit_errors,error_count*16);
requires map_count<1 || map_count>8192 || readable_bytes(vm_jit_map,map_count*8);
modifies bytes(output,size);
ensures result==0 || result==1;
ensures result==0 || (branch_count>=0 && branch_count<=8192 && error_count>=0 && error_count<=32768 && map_count>=1 && map_count<=8192);
PRODUCTION_ORDER_PROLOGUE
    invariant branch_row>=0 && branch_row<=branch_count;
    invariant error_row>=0 && error_row<=error_count;
    invariant frontier>=0 && frontier<=size;
    decreases 9223372036854775807^frontier;
PRODUCTION_ORDER_LOOP
        proof {jit_cross_optional_row(branches,branch_row,branch_count);}
PRODUCTION_BRANCH_READ
        proof {jit_cross_optional_row(errors,error_row,error_count);}
PRODUCTION_ERROR_READ
        proof {jit_cross_choice(branch_row,error_row,branch_count,error_count,branch,error,size);}
PRODUCTION_ORDER_CHOICE
        proof {
            jit_cross_bounds(branch_row,error_row,branch_count,error_count,frontier,site,size,branch,error,next_branch);
            jit_branch_patch_span(output,size,site);
        }
PRODUCTION_BRANCH_WRITE
PRODUCTION_ORDER_ADVANCE
PRODUCTION_ORDER_RETURN

requires next==0 || next==1;
requires site>=1 && site<=size-4 && size<=67108864 && vm_mode==0;
requires row>=0 && row<=8192;
requires next==0 || readable_bytes(branches+row*16,16);
requires map_count>=1 && map_count<=8192;
requires readable_bytes(vm_jit_map,map_count*8);
requires writable_bytes(output+site,4);
modifies bytes(output+site,4);
ensures result==0 || result==1;
PRODUCTION_PATCH_PROLOGUE
    proof {jit_branch_map_slot(vm_jit_map,index,map_count);}
PRODUCTION_PATCH_TARGET
PRODUCTION_PATCH_STORE
PRODUCTION_PATCH_RETURN

// Shared read, bounds, and termination lemmas.
requires b>=0 && b<=bc && bc<=8192;
requires e>=0 && e<=ec && ec<=32768;
requires size>=0 && size<=67108864;
requires frontier>=0 && frontier<=size;
requires site>=frontier;
requires next==0 || next==1;
requires next==0 || (b<bc && site==branch && branch>=1 && branch<=size-4);
requires next==1 || (e<ec && site==error && error>=2 && error<=size-4);
ensures site>=1 && site<=size-4;
ensures site+4>=0 && site+4<=size;
ensures (9223372036854775807^(site+4))>=0;
ensures (9223372036854775807^(site+4))<(9223372036854775807^frontier);
ensures b+next>=0 && b+next<=bc;
ensures e+(1-next)>=0 && e+(1-next)<=ec;
lemma fn jit_cross_bounds(b,e,bc,ec,frontier,site,size,branch,error,next) {
    jit_cross_advance(b,e,bc,ec,next);
    assert site>=1 && site<=size-4;
    assert site+4>=0 && site+4<=size;
    assert site<=67108860;
    jit_cross_rank(frontier,site);
}

// Row loading and cursor bounds shared by both profiles.
requires i>=0 && i<count && count<=32768;
requires readable_bytes(base,count*16);
ensures readable_bytes(base+i*16,16);
lemma fn jit_cross_row_grant(base,i,count) {
    assert i<=32767 && i+1<=count;
    assert i*16>=0 && i*16<=count*16-16;
}

requires size>=0 && size<=67108864;
requires minimum>=1 && minimum<=2;
requires cursor>=0 && cursor<=count && count<=32768;
requires cursor==count || readable_bytes(table+cursor*16,16);
modifies nothing;
ensures result>= -1 && result<=size;
ensures cursor!=count || result==size;
ensures cursor>=count || result== -1 || (result>=minimum && result<=size-4);
ensures cursor==count || result== -1 || result==load64(table+cursor*16);
PRODUCTION_SITE_LOADER

requires b>=0 && b<=bc && bc<=8192;
requires e>=0 && e<=ec && ec<=32768;
requires b<bc || e<ec;
requires size>=0 && size<=67108864;
requires branch>=0 && branch<=size && error>=0 && error<=size;
requires b!=bc || branch==size;
requires e!=ec || error==size;
requires b>=bc || (branch>=1 && branch<=size-4);
requires e>=ec || (error>=2 && error<=size-4);
ensures branch>=error || (b<bc && branch>=1 && branch<=size-4);
ensures branch<error || (e<ec && error>=2 && error<=size-4);
lemma fn jit_cross_choice(b,e,bc,ec,branch,error,size) {
    if branch<error {
        assert branch<size;
        assert b<bc;
        return 0;
    }
    if e==ec {
        assert error==size && branch==size;
        assert b==bc;
    }
}

requires b>=0 && b<=bc && bc<=8192;
requires e>=0 && e<=ec && ec<=32768;
requires next==0 || next==1;
requires next==0 || b<bc;
requires next==1 || e<ec;
ensures b+next>=0 && b+next<=bc;
ensures e+(1-next)>=0 && e+(1-next)<=ec;
lemma fn jit_cross_advance(b,e,bc,ec,next) {
    if next==1 {
        assert next==1;
        assert b<bc && b+1<=bc;
        return 0;
    }
    assert next==0;
    assert e<ec && e+1<=ec;
}

requires i>=0 && i<=count && count<=32768;
requires readable_bytes(base,count*16);
ensures i==count || readable_bytes(base+i*16,16);
lemma fn jit_cross_optional_row(base,i,count) {
    if i==count {return 0;}
    jit_cross_row_grant(base,i,count);
}

requires frontier>=0 && site>=frontier;
requires site<=67108860;
ensures (9223372036854775807^(site+4))>=0;
ensures (9223372036854775807^(site+4))<(9223372036854775807^frontier);
lemma fn jit_cross_rank(frontier,site) {
    assert site+4>site;
    assert site+4>frontier;
}

requires offset>=1 && offset<=size-4 && size<=67108864;
requires writable_bytes(base,size);
ensures offset+4>=0 && offset+4<=size;
ensures writable_bytes(base+offset,4);
lemma fn jit_branch_patch_span(base,size,offset) {
    assert offset<=67108860;
    assert offset<=size-4;
    assert offset+4>=0 && offset+4<=size;
    assert writable_bytes(base+offset,4);
}

requires index>=1 && index<count && count<=8192;
requires readable_bytes(base,count*8);
ensures readable_bytes(base+index*8,8);
lemma fn jit_branch_map_slot(base,index,count) {
    assert index<=8191;
    assert index*8>=0 && index*8<=count*8-8;
}

PRODUCTION_PATCH32
