// Pointwise effects of the production reachability cleanup pass.

requires readable_bytes(io_flags+pc/16,1);
requires writable_bytes(io_flags+pc/16,1);
modifies bytes(io_flags+pc/16,1);
ensures result==0;
ensures load8(io_flags+pc/16)==(old(load8(io_flags+pc/16))&254);
// Production io_drop.

requires start>=0 && start<=end && end<=268435456;
requires observed>=0 && observed<end;
requires (start&15)==0 && (observed&15)==0 && (end&15)==0;
requires writable_bytes(io_flags,end/16);
requires readable_bytes(io_flags+observed/16,1);
modifies ir_opt_dead,bytes(io_flags,end/16);
ensures result==0;
ensures observed>=start || load8(io_flags+observed/16)==old(load8(io_flags+observed/16));
ensures (old(load8(io_flags+observed/16))&4)==0 || load8(io_flags+observed/16)==old(load8(io_flags+observed/16));
ensures observed<start || (old(load8(io_flags+observed/16))&4)!=0 || load8(io_flags+observed/16)==(old(load8(io_flags+observed/16))&254);
fn io_reach_sweep_observed(start,end,observed) {
    let pc=start;
    ghost let watch=io_flags+observed/16;
    ghost let initial=load8(watch);
    ghost let kept=initial&(254|((initial&4)>>2)|(observed<start));
    invariant pc>=start;
    invariant pc>=0;
    invariant pc<=end;
    invariant (pc&15)==0;
    invariant pc>observed || load8(watch)==initial;
    invariant pc<=observed || load8(watch)==kept;
    decreases end-pc;
    while pc<end {
        ghost let at=io_flags+pc/16;
        ghost let before=pc;
        proof {
            io_next_bounded_step(pc,end);
            io_queue_flag_index(pc,end);
            assert writable_bytes(at,1);
            assert readable_bytes(at,1);
            if pc!=observed {io_queue_distinct_flags(io_flags,pc,observed,end);}
        }
        ghost let flag=load8(at);
        ghost let old_watch=load8(watch);
        if io_live(pc) && !(load8(io_flags+pc/16)&4) {
            io_drop(pc);
            ir_opt_dead=ir_opt_dead+1;
            proof {
                if pc==observed {
                    assert observed>=start;
                    assert at==watch;
                    assert (initial&4)==0;
                    assert flag==initial;
                    assert load8(watch)==(initial&254);
                }else {
                    assert disjoint_bytes(at,1,watch,1);
                    assert load8(watch)==old_watch;
                }
            }
        }else {
            proof {
                if pc==observed {
                    assert observed>=start;
                    assert at==watch;
                    assert flag==initial;
                    if (initial&4)==0 {
                        assert (initial&1)==0;
                        assert initial==(initial&254);
                    }
                }
            }
        }
        proof {
            if pc<observed {
                assert pc<=observed-16;
                assert load8(watch)==initial;
            }else {
                assert load8(watch)==kept;
            }
        }
        pc=pc+16;
        proof {
            assert pc>=before;
            assert pc<=end;
            if pc<=observed {
                assert before<observed;
                assert load8(watch)==initial;
            }else {
                assert before>=observed;
                assert load8(watch)==kept;
            }
        }
    }
    proof {
        assert pc==end;
        assert load8(watch)==kept;
        if observed<start || (initial&4)!=0 {assert kept==initial;}
        else {assert kept==(initial&254);}
    }
    return 0;
}
