// General scan safety, including empty tables and invalid counts.
requires size>=0 && size<=67108864;
requires branch_count<0 || branch_count>8192 || readable_bytes(branches,branch_count*16);
requires error_count<0 || error_count>32768 || readable_bytes(errors,error_count*16);
modifies nothing;
ensures result==0 || result==1;
ensures result==0 || (branch_count>=0 && branch_count<=8192 && error_count>=0 && error_count<=32768);
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
        proof {
            jit_cross_choice(branch_row,error_row,branch_count,error_count,branch,error,size);
        }
PRODUCTION_ORDER_CHOICE
        proof {
            jit_cross_bounds(branch_row,error_row,branch_count,error_count,frontier,site,size,branch,error,next_branch);
        }
PRODUCTION_ORDER_ADVANCE
PRODUCTION_ORDER_RETURN

requires b>=0 && b<=bc && bc<=8192;
requires e>=0 && e<=ec && ec<=32768;
requires size>=0 && size<=67108864;
requires frontier>=0 && frontier<=size;
requires site>=frontier;
requires next==0 || next==1;
requires next==0 || (b<bc && site==branch && branch>=1 && branch<=size-4);
requires next==1 || (e<ec && site==error && error>=2 && error<=size-4);
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

ORDER_SHARED_LEMMAS
