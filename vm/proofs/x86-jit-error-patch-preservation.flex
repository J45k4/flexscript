// The gate supplies the checked native patch32. Observe an earlier displacement
// and a disjoint error record across one later patch.
requires vm_mode==0;
requires observed>=2 && observed<=67108860;
requires at>=observed+4 && at<=67108860;
requires writable_bytes(output+at,4);
requires writable_bytes(output+observed,4);
requires readable_bytes(record,16);
requires disjoint_bytes(output+at,4,record,16);
modifies bytes(output+at,4);
ensures result==0;
ensures load64(record)==old(load64(record));
ensures load64(record+8)==old(load64(record+8));
ensures load8(output+observed)==old(load8(output+observed));
ensures load8(output+observed+1)==old(load8(output+observed+1));
ensures load8(output+observed+2)==old(load8(output+observed+2));
ensures load8(output+observed+3)==old(load8(output+observed+3));
fn jit_error_later_patch_preserves(at,value,observed,record) {
    proof {jit_error_ordered_patches(output,observed,at);}
    return patch32(at,value);
}

requires writable_bytes(base+earlier,4);
requires writable_bytes(base+later,4);
requires earlier>=2 && earlier<=67108860;
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

requires earlier>=2 && earlier<=67108860;
requires later>=earlier+4 && later<=67108860;
ensures (base+earlier)-(base+later)<=-4;
lemma fn jit_error_patch_address_order(base,earlier,later) {
    assert earlier-later<=-4;
    assert (base+earlier)-(base+later)==earlier-later;
}

requires writable_bytes(at,4);
ensures at>0 && at<=9223372036854775804;
lemma fn jit_error_four_byte_address(at) {}

