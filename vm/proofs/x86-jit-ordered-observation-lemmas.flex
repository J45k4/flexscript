// Helpers for observing a selected displacement and its record after a patch.

requires i==watch;
ensures base+i*16==base+watch*16;
lemma fn jit_cross_address(base,i,watch) {}

requires actual==watched;
requires readable_bytes(actual,16) && readable_bytes(watched,16);
requires load64(actual)==value && load64(watched)==expected;
ensures value==expected;
lemma fn jit_cross_load(actual,watched,value,expected) {}

requires writable_bytes(base+earlier,4);
requires writable_bytes(base+later,4);
requires earlier>=1 && earlier<=67108860;
requires later>=earlier+4 && later<=67108860;
ensures disjoint_bytes(base+earlier,4,base+later,4);
lemma fn jit_error_ordered_patches(base,earlier,later) {
    jit_error_four_byte_address(base+earlier);
    jit_error_four_byte_address(base+later);
    jit_error_patch_address_order(base,earlier,later);
    jit_error_patches_separated(base+earlier,base+later);
}

requires left>0 && left<=9223372036854775804;
requires right>0 && right<=9223372036854775804;
requires left-right<=-4;
ensures disjoint_bytes(left,4,right,4);
lemma fn jit_error_patches_separated(left,right) {
    assert left!=right;
}

requires earlier>=1 && earlier<=67108860;
requires later>=earlier+4 && later<=67108860;
ensures (base+earlier)-(base+later)<=-4;
lemma fn jit_error_patch_address_order(base,earlier,later) {
    assert earlier-later<=-4;
    assert (base+earlier)-(base+later)==earlier-later;
}

requires writable_bytes(at,4);
ensures at>0 && at<=9223372036854775804;
lemma fn jit_error_four_byte_address(at) {}

requires disjoint_bytes(right,4,left,4);
ensures disjoint_bytes(left,4,right,4);
lemma fn jit_cross_flip_spans(left,right) {}

requires lane>=0 && lane<4;
requires observed==base+lane;
requires writable_bytes(base,4) && writable_bytes(at,4);
requires readable_bytes(observed,1);
requires disjoint_bytes(at,4,base,4);
ensures disjoint_bytes(at,4,observed,1);
lemma fn jit_merged_lane_disjoint(at,base,observed,lane) {
    if lane==0 {
        assert observed==base;
        assert disjoint_bytes(at,4,base,1);
        jit_cross_byte_alias(at,base,observed);
        return 0;
    }
    if lane==1 {
        assert observed==base+1;
        assert disjoint_bytes(at,4,base+1,1);
        jit_cross_byte_alias(at,base+1,observed);
        return 0;
    }
    if lane==2 {
        assert observed==base+2;
        assert disjoint_bytes(at,4,base+2,1);
        jit_cross_byte_alias(at,base+2,observed);
        return 0;
    }
    assert observed==base+3;
    assert disjoint_bytes(at,4,base+3,1);
    jit_cross_byte_alias(at,base+3,observed);
}

requires address==observed;
requires disjoint_bytes(at,4,address,1);
ensures disjoint_bytes(at,4,observed,1);
lemma fn jit_cross_byte_alias(at,address,observed) {}
