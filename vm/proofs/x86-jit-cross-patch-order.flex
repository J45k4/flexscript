// The gate inserts the production scan and row loader. The watched globals
// occur only in annotations and range over arbitrary records from both tables.
global watched_b=0;
global watched_e=0;
global branch_at=0;
global error_at=0;

requires branch_count>=1 && branch_count<=8192 && error_count>=1 && error_count<=32768;
requires size>=0 && size<=67108864;
requires readable_bytes(branches,branch_count*16);
requires readable_bytes(errors,error_count*16);
requires watched_b>=0 && watched_b<branch_count && watched_e>=0 && watched_e<error_count;
requires readable_bytes(branches+watched_b*16,16);
requires readable_bytes(errors+watched_e*16,16);
requires load64(branches+watched_b*16)==branch_at;
requires load64(errors+watched_e*16)==error_at;
modifies nothing;
ensures result==0 || (branch_at>=1 && branch_at<=size-4 && error_at>=2 && error_at<=size-4);
ensures result==0 || branch_at+4<=error_at || error_at+4<=branch_at;
PRODUCTION_ORDER_PROLOGUE
    invariant branch_row>=0 && branch_row<=branch_count;
    invariant error_row>=0 && error_row<=error_count;
    invariant frontier>=0 && frontier<=size;
    invariant branch_row<=watched_b || (branch_at>=1 && branch_at<=size-4);
    invariant error_row<=watched_e || (error_at>=2 && error_at<=size-4);
    invariant branch_row<=watched_b || frontier>=branch_at+4;
    invariant error_row<=watched_e || frontier>=error_at+4;
    invariant branch_row<=watched_b || error_row<=watched_e || branch_at+4<=error_at || error_at+4<=branch_at;
    // For nonnegative offsets, flipping the low 63 bits reverses their order.
    decreases 9223372036854775807^frontier;
PRODUCTION_ORDER_LOOP
        proof {jit_cross_optional_row(branches,branch_row,branch_count);}
PRODUCTION_BRANCH_READ
        proof {jit_cross_optional_row(errors,error_row,error_count);}
PRODUCTION_ERROR_READ
        proof {
            if branch_row==watched_b {
                jit_cross_address(branches,branch_row,watched_b);
                jit_cross_load(branches+branch_row*16,branches+watched_b*16,branch,branch_at);
            }
            if error_row==watched_e {
                jit_cross_address(errors,error_row,watched_e);
                jit_cross_load(errors+error_row*16,errors+watched_e*16,error,error_at);
            }
            assert branch_row!=watched_b || branch==branch_at;
            assert error_row!=watched_e || error==error_at;
            jit_cross_choice(branch_row,error_row,branch_count,error_count,branch,error,size);
        }
PRODUCTION_ORDER_CHOICE
        proof {
            jit_cross_commit(branch_row,error_row,branch_count,error_count,watched_b,watched_e,branch_at,error_at,frontier,site,size,branch,error,next_branch);
        }
PRODUCTION_ORDER_ADVANCE
    proof {jit_cross_done(branch_row,error_row,branch_count,error_count,watched_b,watched_e);}
PRODUCTION_ORDER_RETURN

requires i==watch;
ensures base+i*16==base+watch*16;
lemma fn jit_cross_address(base,i,watch) {}

requires actual==watched;
requires readable_bytes(actual,16) && readable_bytes(watched,16);
requires load64(actual)==value && load64(watched)==expected;
ensures value==expected;
lemma fn jit_cross_load(actual,watched,value,expected) {}

requires i>=0 && i<32768 && j>=0 && j<=32768;
requires watch_i>=0 && watch_i<32768 && watch_j>=0 && watch_j<32768;
requires size>=0 && size<=67108864;
requires frontier>=0 && frontier<=size;
requires site>=1 && site<=size-4 && site>=frontier;
requires i!=watch_i || site==a;
requires i<=watch_i || frontier>=a+4;
requires j<=watch_j || frontier>=b+4;
requires i<=watch_i || j<=watch_j || a+4<=b || b+4<=a;
ensures site+4>=0 && site+4<=size;
ensures (9223372036854775807^(site+4))>=0;
ensures (9223372036854775807^(site+4))<(9223372036854775807^frontier);
ensures i+1<=watch_i || site+4>=a+4;
ensures j<=watch_j || site+4>=b+4;
ensures i+1<=watch_i || j<=watch_j || a+4<=b || b+4<=a;
lemma fn jit_cross_step(i,j,watch_i,watch_j,a,b,frontier,site,size) {
    assert site+4>=0 && site+4<=size;
    assert site<=67108860;
    jit_cross_rank(frontier,site);
    if j>watch_j {assert frontier>=b+4;}
    if i<watch_i {
        assert i+1<=watch_i;
        return 0;
    }
    if i==watch_i {
        assert site==a;
        if j>watch_j {assert b+4<=a;}
        return 0;
    }
    assert frontier>=a+4;
}

requires b>=bc && e>=ec;
requires watched_b<bc && watched_e<ec;
ensures b>watched_b && e>watched_e;
lemma fn jit_cross_done(b,e,bc,ec,watched_b,watched_e) {}

requires b>=0 && b<=bc && bc<=8192;
requires e>=0 && e<=ec && ec<=32768;
requires watched_b>=0 && watched_b<bc && watched_e>=0 && watched_e<ec;
requires size>=0 && size<=67108864;
requires frontier>=0 && frontier<=size;
requires site>=frontier;
requires next==0 || next==1;
requires next==0 || (b<bc && site==branch && branch>=1 && branch<=size-4);
requires next==1 || (e<ec && site==error && error>=2 && error<=size-4);
requires b!=watched_b || branch==branch_at;
requires e!=watched_e || error==error_at;
requires b<=watched_b || (branch_at>=1 && branch_at<=size-4);
requires e<=watched_e || (error_at>=2 && error_at<=size-4);
requires b<=watched_b || frontier>=branch_at+4;
requires e<=watched_e || frontier>=error_at+4;
requires b<=watched_b || e<=watched_e || branch_at+4<=error_at || error_at+4<=branch_at;
ensures site+4>=0 && site+4<=size;
ensures (9223372036854775807^(site+4))>=0;
ensures (9223372036854775807^(site+4))<(9223372036854775807^frontier);
ensures b+next>=0 && b+next<=bc;
ensures e+(1-next)>=0 && e+(1-next)<=ec;
ensures b+next<=watched_b || (branch_at>=1 && branch_at<=size-4);
ensures e+(1-next)<=watched_e || (error_at>=2 && error_at<=size-4);
ensures b+next<=watched_b || site+4>=branch_at+4;
ensures e+(1-next)<=watched_e || site+4>=error_at+4;
ensures b+next<=watched_b || e+(1-next)<=watched_e || branch_at+4<=error_at || error_at+4<=branch_at;
lemma fn jit_cross_commit(b,e,bc,ec,watched_b,watched_e,branch_at,error_at,frontier,site,size,branch,error,next) {
    jit_cross_advance(b,e,bc,ec,next);
    if next {
        assert next==1;
        if b<watched_b {assert b+1<=watched_b;}
        if b==watched_b {assert branch_at>=1 && branch_at<=size-4;}
        jit_cross_step(b,e,watched_b,watched_e,branch_at,error_at,frontier,site,size);
        return 0;
    }
    assert next==0;
    if e<watched_e {assert e+1<=watched_e;}
    if e==watched_e {assert error_at>=2 && error_at<=size-4;}
    jit_cross_step(e,b,watched_e,watched_b,error_at,branch_at,frontier,site,size);
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
