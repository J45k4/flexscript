// Selected worklist insertion followed by production cleanup.

requires pc>=0 && pc<=end && end<=268435456;
requires (pc&15)==0 && (end&15)==0;
requires observed>=pc && observed<end && (observed&15)==0;
requires start>=0 && start<=end && end<=268435456;
requires start>=0 && start<=pc && (start&15)==0;
requires used>=0 && used<end/16;
requires writable_bytes(io_flags,end/16);
requires readable_bytes(io_flags,end/16);
requires readable_bytes(io_flags+observed/16,1);
requires (load8(io_flags+observed/16)&1)==1;
requires writable_bytes(io_work+used*8,8);
requires disjoint_bytes(io_flags,end/16,io_work+used*8,8);
modifies ir_opt_dead,bytes(io_flags,end/16),bytes(io_work+used*8,8);
ensures result==used || result==used+1;
ensures result==used || (load8(io_flags+load64(io_work+used*8)/16)&5)==5;

fn io_enqueue_then_sweep(start,pc,end,used,observed) {
    pc=io_next_observed(pc,end,observed);
    proof {
        assert pc<=observed && observed<end;
        io_queue_flag_grant(io_flags,pc,end,io_work+used*8);
    }
    if pc>=end {return -1;}
    if !(load8(io_flags+pc/16)&4) {
        proof {assert (load8(io_flags+pc/16)&1)==1;}
        store8(io_flags+pc/16,load8(io_flags+pc/16)|4);
        store64(io_work+used*8,pc);
        proof {
            assert load64(io_work+used*8)==pc;
            assert disjoint_bytes(io_flags+pc/16,1,io_work+used*8,8);
            assert (load8(io_flags+pc/16)&5)==5;
            assert readable_bytes(io_flags+pc/16,1);
            assert pc>=0 && pc<end && (pc&15)==0;
        }
        let marked=load8(io_flags+pc/16);
        io_reach_sweep_keeps_marked(start,end,pc,marked);
        proof {
            assert disjoint_bytes(io_flags,end/16,io_work+used*8,8);
            assert load64(io_work+used*8)==pc;
            assert (marked&5)==5;
            assert (marked&4)!=0;
            assert load8(io_flags+pc/16)==marked;
            ghost let saved=load64(io_work+used*8);
            assert saved==pc;
            assert io_flags+saved/16==io_flags+pc/16;
            assert readable_bytes(io_flags+saved/16,1);
            io_queue_flag_alias(io_flags+pc/16,io_flags+load64(io_work+used*8)/16);
            assert (load8(io_flags+load64(io_work+used*8)/16)&5)==5;
        }
        return used+1;
    }
    io_reach_sweep_observed(start,end,observed);
    return used;
}

requires start>=0 && start<=end && end<=268435456;
requires observed>=0 && observed<end;
requires (start&15)==0 && (observed&15)==0 && (end&15)==0;
requires writable_bytes(io_flags,end/16);
requires readable_bytes(io_flags+observed/16,1);
requires load8(io_flags+observed/16)==flag;
requires (flag&5)==5;
modifies ir_opt_dead,bytes(io_flags,end/16);
ensures result==0;
ensures load8(io_flags+observed/16)==flag;
fn io_reach_sweep_keeps_marked(start,end,observed,flag) {
    return io_reach_sweep_observed(start,end,observed);
}

requires at==alias;
requires readable_bytes(at,1);
ensures readable_bytes(alias,1);
ensures load8(alias)==load8(at);
lemma fn io_queue_flag_alias(at,alias) {}
