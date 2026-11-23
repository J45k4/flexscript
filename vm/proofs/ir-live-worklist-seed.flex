// Production first queue insertion and reachability cursors.

requires start>=0 && start<end && end<=268435456;
requires (start&15)==0 && (end&15)==0;
requires writable_bytes(io_flags,end/16);
requires readable_bytes(io_flags,end/16);
requires readable_bytes(io_flags+start/16,1);
requires (load8(io_flags+start/16)&5)==1;
requires writable_bytes(io_work,8);
requires disjoint_bytes(io_flags,end/16,io_work,8);
requires pc==start && used==0;
modifies bytes(io_flags,end/16),bytes(io_work,8);
ensures result==1;
ensures load64(io_work)==start;
ensures load8(io_flags+start/16)==(old(load8(io_flags+start/16))|4);
ensures (load8(io_flags+start/16)&5)==5;
fn io_enqueue_seed(pc,end,used,start) {
    ghost let entry_flag=load8(io_flags+start/16);
    pc=io_next_observed(pc,end,start);
    proof {
        assert pc==start;
        assert used*8==0;
        assert io_work+used*8==io_work;
        assert io_flags+pc/16==io_flags+start/16;
        assert load8(io_flags+pc/16)==entry_flag;
        io_queue_flag_grant(io_flags,pc,end,io_work);
        io_worklist_zero_word(io_work,used);
    }
    if pc>=end {return -1;}
    if !(load8(io_flags+pc/16)&4) {store8(io_flags+pc/16,load8(io_flags+pc/16)|4);store64(io_work+used*8,pc);
        proof {
            assert load64(io_work)==start;
            assert load8(io_flags+start/16)==(entry_flag|4);
            io_worklist_first_mark(load8(io_flags+start/16),entry_flag);
        }
        return used+1;
    }
    proof {assert 0;}
    return used;
}

requires start>=0 && start<end && end<=268435456;
requires (start&15)==0 && (end&15)==0;
requires writable_bytes(io_flags,end/16);
requires readable_bytes(io_flags,end/16);
requires readable_bytes(io_flags+start/16,1);
requires (load8(io_flags+start/16)&5)==1;
requires writable_bytes(io_work,8);
requires disjoint_bytes(io_flags,end/16,io_work,8);
requires readable_bytes(io_code+start,16);
requires readable_bytes(io_code+start,8);
requires readable_bytes(io_code+start+8,8);
requires load64(io_code+start)==18;
requires disjoint_bytes(io_flags,end/16,io_code+start,8);
requires disjoint_bytes(io_flags,end/16,io_code+start+8,8);
requires disjoint_bytes(io_work,8,io_code+start,8);
requires disjoint_bytes(io_work,8,io_code+start+8,8);
modifies bytes(io_flags,end/16),bytes(io_work,8);
ensures result==1;
ensures load64(io_work)==start;
ensures load64(io_code+start)==18;
ensures load64(io_code+start+8)==old(load64(io_code+start+8));
fn io_reach_seed(start,end) {
    let used=io_enqueue_seed(start,end,0,start);let read=0;
    proof {
        assert used==1;
        assert read==0;
        assert read<used && used<=end/16;
        assert load64(io_work)==start;
        assert load64(io_code+start)==18;
    }
    return used;
}

requires used==0;
requires writable_bytes(work,8);
ensures work+used*8==work;
ensures writable_bytes(work+used*8,8);
lemma fn io_worklist_zero_word(work,used) {}

requires current==(previous|4);
requires (previous&5)==1;
ensures (current&5)==5;
lemma fn io_worklist_first_mark(current,previous) {}
