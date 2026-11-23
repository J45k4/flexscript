// Pointwise proof of the production optimizer successor scan.

requires pc>=0 && pc<=end && end<=268435456;
requires (pc&15)==0 && (end&15)==0;
requires observed>=pc && observed<end && (observed&15)==0;
requires readable_bytes(io_flags,end/16);
requires readable_bytes(io_flags+observed/16,1);
modifies nothing;
ensures result>=old(pc) && result<=end && (result&15)==0;
ensures result==end || result<end && (load8(io_flags+result/16)&1)==1;
ensures result<=observed || (load8(io_flags+observed/16)&1)==0;
fn io_next_observed(pc,end,observed) {
    ghost let start=pc;
    invariant pc>=start;
    invariant pc>=0;
    invariant pc<=end;
    invariant (pc&15)==0;
    invariant pc<=observed || (load8(io_flags+observed/16)&1)==0;
    decreases end-pc;
    while pc<end && !io_live(pc) {
        ghost let before=pc;
        proof {
            assert pc<=end-16;
            io_next_bounded_step(pc,end);
            if pc==observed {
                assert io_flags+pc/16==io_flags+observed/16;
                assert (load8(io_flags+observed/16)&1)==0;
            }
            if pc<observed {assert pc<=observed-16;}
        }
        pc=pc+16;
        proof {
            assert pc>=before;
            assert pc<=end;
        }
    }
    return pc;
}


requires pc>=0 && pc<end;
requires end<=268435456;
requires (pc&15)==0 && (end&15)==0;
ensures pc+16>=pc;
ensures pc+16<=end;
lemma fn io_next_bounded_step(pc,end) {
    assert (pc>>4)<(end>>4);
    assert ((pc+16)>>4)==(pc>>4)+1;
    assert (pc>>4)+1<=(end>>4);
    assert ((pc+16)&15)==0;
}
