// Appending a new entry keeps any earlier marked queue row distinct.

requires pc>=0 && pc<=end && end<=268435456;
requires (pc&15)==0 && (end&15)==0;
requires observed>=pc && observed<end && (observed&15)==0;
requires used>=0 && used<end/16;
requires earlier>=0 && earlier<used;
requires writable_bytes(io_flags,end/16);
requires readable_bytes(io_flags,end/16);
requires writable_bytes(io_work,(end/16)*8);
requires disjoint_bytes(io_flags,end/16,io_work,(end/16)*8);
requires readable_bytes(io_work+earlier*8,8);
requires load64(io_work+earlier*8)==retained;
requires readable_bytes(io_flags+observed/16,1);
requires (load8(io_flags+observed/16)&1)==1;
requires retained>=0 && retained<end && (retained&15)==0;
requires readable_bytes(io_flags+retained/16,1);
requires (load8(io_flags+retained/16)&5)==5;
modifies bytes(io_flags,end/16),bytes(io_work+used*8,8);
ensures result==used || result==used+1;
ensures load64(io_work+earlier*8)==retained;
ensures (load8(io_flags+retained/16)&5)==5;
ensures result==used || load64(io_work+used*8)!=load64(io_work+earlier*8);
fn io_enqueue_preserves_worklist_entry(pc,end,used,observed,earlier,retained) {
    ghost let saved=load64(io_work+earlier*8);
    ghost let old_flags=load8(io_flags+retained/16);
    proof {
        io_worklist_entry_grants(io_work,io_flags,end/16,earlier,used);
        assert saved==retained;
        assert (old_flags&4)!=0;
    }
    let next=io_enqueue_preserves_observed_flag(pc,end,used,observed,retained);
    proof {
        assert disjoint_bytes(io_flags,end/16,io_work+earlier*8,8);
        assert disjoint_bytes(io_work+used*8,8,io_work+earlier*8,8);
        assert load64(io_work+earlier*8)==saved;
        assert load64(io_work+earlier*8)==retained;
        assert load8(io_flags+retained/16)==old_flags;
        assert (load8(io_flags+retained/16)&5)==5;
    }
    if next==used {return next;}
    proof {
        assert load64(io_work+earlier*8)==retained;
        assert load64(io_work+used*8)!=retained;
        assert load64(io_work+used*8)!=load64(io_work+earlier*8);
    }
    return next;
}

requires capacity>=1 && capacity<=16777216;
requires earlier>=0 && earlier<used && used<capacity;
ensures earlier*8>=0 && earlier*8<=capacity*8-8;
ensures used*8>=0 && used*8<=capacity*8-8;
ensures (used-earlier)*8>=8;
lemma fn io_worklist_entry_bounds(capacity,earlier,used) {}

requires capacity>=1 && capacity<=16777216;
requires earlier>=0 && earlier<used && used<capacity;
requires writable_bytes(work,capacity*8);
requires disjoint_bytes(flags,capacity,work,capacity*8);
ensures readable_bytes(work+earlier*8,8);
ensures writable_bytes(work+used*8,8);
ensures disjoint_bytes(flags,capacity,work+earlier*8,8);
ensures disjoint_bytes(flags,capacity,work+used*8,8);
ensures disjoint_bytes(work+used*8,8,work+earlier*8,8);
ensures (used-earlier)*8>=8;
lemma fn io_worklist_entry_grants(work,flags,capacity,earlier,used) {
    io_worklist_entry_bounds(capacity,earlier,used);
    assert writable_bytes(work+earlier*8,8);
    assert writable_bytes(work+used*8,8);
    assert (work+used*8)-(work+earlier*8)==(used-earlier)*8;
}
