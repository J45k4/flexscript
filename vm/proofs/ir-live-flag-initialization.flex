// Pointwise induction over the production optimizer flag initialization.

requires size>=16 && size<=268435456 && (size&15)==0;
requires observed>=0 && observed<size && (observed&15)==0;
requires writable_bytes(io_flags,size/16);
modifies bytes(io_flags,size/16);
ensures load8(io_flags+observed/16)==1;
fn io_initialize_observed_flag(size,observed) {
    let pc=0;
    invariant pc>=0 && pc<=size && (pc&15)==0;
    invariant observed>=pc || load8(io_flags+observed/16)==1;
    decreases (size>>4)-(pc>>4);
    while pc<size {
        proof {
            io_next_bounded_step(pc,size);
            io_flag_init_rank(pc,size);
            io_queue_flag_index(pc,size);
            if observed<pc {
                io_queue_distinct_flags(io_flags,pc,observed,size);
            }
        }
        store8(io_flags+pc/16,1);
        proof {
            if observed==pc {
                assert io_flags+observed/16==io_flags+pc/16;
                assert load8(io_flags+observed/16)==1;
            }
            if observed>pc {assert observed>=pc+16;}
        }
        pc=pc+16;
    }
    return 0;
}

requires pc>=0 && pc<size && size<=268435456;
requires (pc&15)==0 && (size&15)==0;
ensures (size>>4)-(pc>>4)>=0;
ensures (size>>4)-((pc+16)>>4)<(size>>4)-(pc>>4);
lemma fn io_flag_init_rank(pc,size) {
    assert ((pc+16)>>4)==(pc>>4)+1;
    assert (pc>>4)<(size>>4);
    io_flag_rank_decreases(size>>4,pc>>4,(pc+16)>>4);
}

requires n<=16777216 && index>=0 && index<n;
requires next==index+1;
ensures n-next<n-index;
lemma fn io_flag_rank_decreases(n,index,next) {
    io_flag_rank_successor(n,index);
    io_flag_rank_subtract_alias(n,next,index+1);
}

requires left==right;
ensures n-left==n-right;
lemma fn io_flag_rank_subtract_alias(n,left,right) {}

requires n<=16777216 && index>=0 && index<n;
ensures n-(index+1)<n-index;
lemma fn io_flag_rank_successor(n,index) {
    assert n-index>=1;
    assert n-(index+1)==(n-index)-1;
    assert (n-index)-1<n-index;
}
