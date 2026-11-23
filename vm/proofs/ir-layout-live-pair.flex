// Production layout scan with two live observer slots.

requires earlier>=0 && (earlier&15)==0;
requires later>earlier && (later&15)==0;
requires size>=0 && size<=268435456;
requires later<=size-16;
ensures size>=32;
ensures earlier<=size-16;
lemma fn io_layout_both_live_fit(earlier,later,size) {
    assert (earlier>>4)<(later>>4);
    assert later>=16;
}

// Two arbitrarily separated live slots receive ordered, in-bounds offsets.

requires count>=1 && count<=16777216;
requires observe>=0 && observe<count;
requires later>observe && later<count;
requires writable_bytes(io_map,(count+1)*8);
requires readable_bytes(io_flags,count);
requires disjoint_bytes(io_map,(count+1)*8,io_flags,count);
requires readable_bytes(io_map+observe*8,8);
requires readable_bytes(io_map+later*8,8);
requires readable_bytes(io_flags+observe,1);
requires (load8(io_flags+observe)&1)==1;
requires readable_bytes(io_flags+later,1);
requires (load8(io_flags+later)&1)==1;
modifies bytes(io_map,(count+1)*8);
// Bind the result to the production sentinel before using the result bounds.
ensures load64(io_map+count*8)==result;
ensures result>=32;
ensures result<=count*16;
ensures (result&15)==0;
ensures load64(io_map+observe*8)<load64(io_map+later*8);
ensures load64(io_map+observe*8)>=0 && (load64(io_map+observe*8)&15)==0;
ensures load64(io_map+later*8)>=0 && (load64(io_map+later*8)&15)==0;
ensures load64(io_map+observe*8)<=result-16;
ensures load64(io_map+later*8)<=result-16;
ensures (load8(io_flags+observe)&1)==1;
ensures (load8(io_flags+later)&1)==1;
fn io_build_layout_ordered_live_pair(count,observe,later) {
    let bytes=0;
    let i=0;
    proof {
        assert observe<=count-1;
        io_layout_observed_flag(io_map,io_flags,count,observe);
        assert later<=count-1;
        io_layout_observed_flag(io_map,io_flags,count,later);
    }
    invariant i>=0 && i<=count;
    invariant bytes>=0;
    invariant bytes<=i*16;
    invariant (bytes&15)==0;
    invariant writable_bytes(io_map,(count+1)*8);
    invariant readable_bytes(io_flags,count);
    invariant (load8(io_flags+observe)&1)==1;
    invariant (load8(io_flags+later)&1)==1;
    invariant (i<=observe) | ((load64(io_map+observe*8)>=0) & ((load64(io_map+observe*8)&15)==0));
    invariant (i<=later) | ((load64(io_map+later*8)>=0) & ((load64(io_map+later*8)&15)==0));
    invariant (i<=later) | (load64(io_map+later*8)<=bytes-16);
    invariant (i<=observe) | (load64(io_map+observe*8)<bytes);
    invariant (i<=later) | (load64(io_map+observe*8)<load64(io_map+later*8));
    decreases count-i;
    while i<count {
        proof {
            io_layout_index(i,count);
            io_layout_region(io_map,io_flags,i,count);
            io_layout_progress(bytes,i,count);
        }
        ghost let a=load64(io_map+observe*8);
        ghost let b=load64(io_map+later*8);
        ghost let before=bytes;
        proof {
            io_layout_observed_crossing(i,observe);
            io_layout_observed_crossing(i,later);
            io_layout_flag_separation(io_map,io_flags,count,i,observe);
            io_layout_flag_separation(io_map,io_flags,count,i,later);
            if i>observe {io_layout_previous_word(io_map,i,observe,count);}
            if i>later {io_layout_previous_word(io_map,i,later,count);}
        }
        store64(io_map+i*8,bytes);
        let live=load8(io_flags+i)&1;
        ghost let aa=load64(io_map+observe*8);
        ghost let bb=load64(io_map+later*8);
        proof {
            assert live==0 || live==1;
            io_layout_advance(bytes,i,count,live);
            if i==observe {
                io_layout_observer_addresses(io_map,io_flags,i,observe);
                io_layout_same_flag(io_flags+i,io_flags+observe);
                assert live==1;
                io_layout_same_word(io_map+i*8,io_map+observe*8);
                assert aa==bytes;
            }
            if i>observe {assert aa==a;}
            if i>later {assert bb==b;}
            if i==later {
                io_layout_observer_addresses(io_map,io_flags,i,later);
                io_layout_same_flag(io_flags+i,io_flags+later);
                assert live==1;
                io_layout_same_word(io_map+i*8,io_map+later*8);
                assert bb==bytes;
                io_layout_second_follows_first(i,observe,later);
                io_layout_seen_less(i,observe,a,aa,bytes);
            }
            assert (i<=observe) | (a==aa);
            assert (i<=later) | (b==bb);
            assert (i!=later) | ((aa<bytes) & (bb==bytes));
            io_layout_order_induction(i,observe,later,a,b,aa,bb,bytes);
        }
        bytes=bytes+live*16;
        proof {
            assert bytes>=before;
            if i==observe {
                assert aa<bytes;
                assert aa>=0 && (aa&15)==0;
            }
            if i==later {
                assert bb>=0 && (bb&15)==0;
                assert bytes-16==bb;
                assert bb<=bytes-16;
            }
            if i>later {
                assert b>=0 && (b&15)==0;
                assert b<=before-16;
                assert before<=268435440;
                assert bytes<=268435456;
                io_layout_keep_limit(b,before,bytes);
                assert bb==b;
                io_layout_observed_bound(bb,b,bytes);
            }
            if i>observe {
                io_layout_seen_less(i,observe,a,aa,before);
                io_layout_cursor_monotone(aa,before,bytes);
            }
        }
        proof {
            assert bytes>=0;
            assert bytes<=(i+1)*16;
            assert (bytes&15)==0;
            io_layout_rank_step(i,count);
        }
        i=i+1;
    }
    proof {assert count*8>=0 && count*8+8==(count+1)*8;}
    ghost let a=load64(io_map+observe*8);
    ghost let b=load64(io_map+later*8);
    proof {
        assert i==count;
        assert i>later;
        assert a<b;
        io_layout_previous_word(io_map,count,observe,count);
        io_layout_previous_word(io_map,count,later,count);
        io_layout_flag_separation(io_map,io_flags,count,count,observe);
        io_layout_flag_separation(io_map,io_flags,count,count,later);
        io_layout_both_live_fit(a,b,bytes);
    }
    store64(io_map+count*8,bytes);
    proof {
        assert load64(io_map+observe*8)==a;
        assert load64(io_map+later*8)==b;
        io_layout_order_preserved(load64(io_map+observe*8),load64(io_map+later*8),a,b);
    }
    return bytes;
}
