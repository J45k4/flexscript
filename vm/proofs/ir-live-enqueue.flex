// Queue insertion and preservation of an arbitrary observed flag.

requires pc>=0 && pc<=end && end<=268435456;
requires (pc&15)==0 && (end&15)==0;
requires observed>=pc && observed<end && (observed&15)==0;
requires used>=0 && used<end/16;
requires writable_bytes(io_flags,end/16);
requires readable_bytes(io_flags,end/16);
requires readable_bytes(io_flags+observed/16,1);
requires (load8(io_flags+observed/16)&1)==1;
requires retained>=0 && retained<end && (retained&15)==0;
requires readable_bytes(io_flags+retained/16,1);
requires writable_bytes(io_work+used*8,8);
requires disjoint_bytes(io_flags,end/16,io_work+used*8,8);
modifies bytes(io_flags,end/16),bytes(io_work+used*8,8);
ensures result==used || result==used+1;
ensures (load8(io_flags+observed/16)&1)==1;
ensures (load8(io_flags+retained/16)&251)==(old(load8(io_flags+retained/16))&251);
ensures (old(load8(io_flags+retained/16))&4)==0 || load8(io_flags+retained/16)==old(load8(io_flags+retained/16));
ensures (old(load8(io_flags+retained/16))&4)==0 || result==used || load64(io_work+used*8)!=retained;
ensures result==used || (load64(io_work+used*8)&15)==0;
ensures result==used || load64(io_work+used*8)>=old(pc);
ensures result==used || load64(io_work+used*8)<=observed;
ensures result!=used || load64(io_work+used*8)==old(load64(io_work+used*8));
ensures result==used || (load8(io_flags+load64(io_work+used*8)/16)&5)==5;
fn io_enqueue_preserves_observed_flag(pc,end,used,observed,retained) {
    ghost let old_retained=load8(io_flags+retained/16);
    ghost let start=pc;
    pc=io_next_observed(pc,end,observed);
    proof {
        assert pc<=observed && observed<end;
        io_queue_flag_grant(io_flags,pc,end,io_work+used*8);
    }
    // The proof excludes the production failure branch on this path.
    if pc>=end {return -1;}
    if !(load8(io_flags+pc/16)&4) {
        proof {
            io_queue_flag_grant(io_flags,observed,end,io_work+used*8);
            if pc!=observed {io_queue_distinct_flags(io_flags,pc,observed,end);}
            io_queue_flag_grant(io_flags,retained,end,io_work+used*8);
            if pc==retained {
                io_queue_equal_flag(io_flags,pc,retained);
                assert (old_retained&4)==0;
            }else {
                io_queue_distinct_flags(io_flags,pc,retained,end);
            }
        }
        proof {assert (load8(io_flags+pc/16)&1)==1;}
        store8(io_flags+pc/16,load8(io_flags+pc/16)|4);
        store64(io_work+used*8,pc);
        proof {
            assert load64(io_work+used*8)==pc;
            assert disjoint_bytes(io_flags+pc/16,1,io_work+used*8,8);
            assert (load8(io_flags+pc/16)&5)==5;
            assert pc>=start && pc<=observed && (pc&15)==0;
            assert load64(io_work+used*8)>=start;
            io_queue_loaded_bound(load64(io_work+used*8),pc,observed);
            assert (load8(io_flags+observed/16)&1)==1;
            assert disjoint_bytes(io_flags+retained/16,1,io_work+used*8,8);
            if pc==retained {
                io_queue_equal_flag(io_flags,pc,retained);
                assert load8(io_flags+retained/16)==(old_retained|4);
                assert (old_retained&4)==0;
            }else {
                assert disjoint_bytes(io_flags+pc/16,1,io_flags+retained/16,1);
                assert load8(io_flags+retained/16)==old_retained;
            }
            assert (load8(io_flags+retained/16)&251)==(old_retained&251);
            assert (old_retained&4)==0 || pc!=retained;
            io_worklist_excludes_marked(old_retained,pc,load64(io_work+used*8),retained);
            io_queue_equal_flag(io_flags,pc,load64(io_work+used*8));
            assert (load8(io_flags+load64(io_work+used*8)/16)&5)==5;
        }
        return used+1;
    }
    return used;
}

requires pc>=0 && pc<end && end<=268435456;
requires (pc&15)==0 && (end&15)==0;
requires writable_bytes(flags,end/16);
requires disjoint_bytes(flags,end/16,word,8);
ensures pc/16>=0;
ensures pc/16<=end/16-1;
ensures writable_bytes(flags+pc/16,1);
ensures disjoint_bytes(flags+pc/16,1,word,8);
lemma fn io_queue_flag_grant(flags,pc,end,word) {
    io_queue_flag_index(pc,end);
    assert pc/16>=0;
    assert pc/16<=end/16-1;
}

requires pc>=0 && pc<end && observed>=0 && observed<end && end<=268435456;
requires (pc&15)==0 && (observed&15)==0 && (end&15)==0;
requires pc!=observed;
requires writable_bytes(flags,end/16);
ensures disjoint_bytes(flags+pc/16,1,flags+observed/16,1);
lemma fn io_queue_distinct_flags(flags,pc,observed,end) {
    assert (pc>>4)!=(observed>>4);
    assert flags+pc/16!=flags+observed/16;
    assert readable_bytes(flags+pc/16,1);
    assert readable_bytes(flags+observed/16,1);
}

requires pc>=0 && pc<end && end<=268435456;
requires (pc&15)==0 && (end&15)==0;
ensures pc/16>=0;
ensures pc/16<=end/16-1;
lemma fn io_queue_flag_index(pc,end) {
    assert pc/16==pc>>4;
    assert end/16==end>>4;
    assert (pc>>4)<(end>>4);
}

requires chosen==alias;
requires readable_bytes(flags+chosen/16,1);
ensures readable_bytes(flags+alias/16,1);
ensures load8(flags+chosen/16)==load8(flags+alias/16);
lemma fn io_queue_equal_flag(flags,chosen,alias) {
    assert chosen/16==alias/16;
    assert flags+chosen/16==flags+alias/16;
}

requires saved==chosen;
requires chosen<=observed;
ensures saved<=observed;
lemma fn io_queue_loaded_bound(saved,chosen,observed) {}


requires chosen==stored;
requires (initial&4)==0 || chosen!=retained;
ensures (initial&4)==0 || stored!=retained;
lemma fn io_worklist_excludes_marked(initial,chosen,stored,retained) {}
