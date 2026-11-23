// Staging budget invariant for the loop over body slots after the prologue.
requires base>=21 && base<=57365;
requires slot>=1 && slot<=8192;
requires current>=base && current<=base+256*(slot-1);
ensures current<=2154261;
ensures current<=67108864-139;
ensures current<=67108864-110;
lemma fn jit_headroom_at_slot(base,slot,current) {
    let used=slot-1;
    assert used>=0 && used<=8191;
    assert 256*used==used<<8;
    assert 256*used>=0 && 256*used<=2096896;
    assert base+256*used<=2154261;
}

requires base>=21 && base<=57365;
requires slot>=1 && slot<8192;
requires current>=base && current<=base+256*(slot-1);
requires next>=current+23 && next<=current+139;
ensures next>=base && next<=base+256*((slot+1)-1);
lemma fn jit_headroom_next_slot(base,slot,current,next) {
    jit_headroom_at_slot(base,slot,current);
    let used=256*(slot-1);
    assert used+256==256*slot;
    assert (slot+1)-1==slot;
    jit_headroom_cursor_advance(base,used,current,next);
}

requires base>=21 && base<=57365;
requires used>=0 && used<=2096896;
requires current>=base && current<=base+used;
requires next>=current+23 && next<=current+139;
ensures next>=base;
ensures next<=base+(used+256);
lemma fn jit_headroom_cursor_advance(base,used,current,next) {
    assert current<=2154261;
    assert base+used>=base && base+used<=2154261;
    assert next>=current;
    assert current+139<=base+used+256;
    assert base+used+256==base+(used+256);
}
