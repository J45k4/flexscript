// Derive selected conditional worklist grants from the two backing spans.

requires capacity>=2 && capacity<=16777216;
requires used>=0 && used<=capacity-2;
ensures used*8>=0;
ensures used*8+16<=capacity*8;
lemma fn io_worklist_reserve_pair_bounds(capacity,used) {
    assert used*8==used<<3;
    assert capacity*8==capacity<<3;
    assert (capacity-2)*8==(capacity-2)<<3;
    assert used*8<=(capacity-2)*8;
    io_worklist_add_pair_extent(used*8,(capacity-2)*8);
    assert (capacity-2)*8+16==capacity*8;
}

requires capacity>=2 && capacity<=16777216;
requires used>=0 && used<=capacity-2;
requires writable_bytes(work,capacity*8);
requires writable_bytes(flags,capacity);
requires disjoint_bytes(flags,capacity,work,capacity*8);
ensures writable_bytes(work+used*8,16);
ensures disjoint_bytes(flags,capacity,work+used*8,16);
lemma fn io_worklist_reserve_pair(flags,work,capacity,used) {
    io_worklist_reserve_pair_bounds(capacity,used);
}

requires left>=0 && left<=right && right<=134217728;
ensures left+16<=right+16;
lemma fn io_worklist_add_pair_extent(left,right) {}

requires capacity>=2 && capacity<=16777216;
requires read>=0 && read<used && used<=capacity-2;
requires writable_bytes(work,capacity*8);
requires writable_bytes(flags,capacity);
requires disjoint_bytes(flags,capacity,work,capacity*8);
ensures readable_bytes(work+read*8,8);
ensures writable_bytes(work+used*8,16);
ensures disjoint_bytes(flags,capacity,work+read*8,8);
ensures disjoint_bytes(flags,capacity,work+used*8,16);
ensures disjoint_bytes(work+used*8,16,work+read*8,8);
lemma fn io_worklist_owned_pair(flags,work,capacity,used,read) {
    io_worklist_entry_grants(work,flags,capacity,read,used);
    io_worklist_reserve_pair(flags,work,capacity,used);
    assert (work+used*8)-(work+read*8)==(used-read)*8;
    assert (used-read)*8>=8;
}

requires capacity>=2 && capacity<=16777216;
requires read>=0 && read<used && used<=capacity-2;
requires writable_bytes(work,capacity*8);
requires writable_bytes(flags,capacity);
requires disjoint_bytes(flags,capacity,work,capacity*8);
modifies nothing;
ensures result==load64(work+read*8);
spec fn io_owned_queue_word(flags,work,capacity,used,read) {
    proof {io_worklist_owned_pair(flags,work,capacity,used,read);}
    return load64(work+read*8);
}

requires end>=32 && end<=268435456 && (end&15)==0;
requires read>=0 && read<used && used<=end/16-2;
requires expected>=0 && expected<=end-16 && (expected&15)==0;
requires expected>=0 && expected<end;
requires target>=0 && target<=end;
requires readable_bytes(io_code+expected,16);
requires load64(io_code+expected)==11 || load64(io_code+expected)==12;
requires load64(io_code+expected+8)==target;
requires writable_bytes(io_flags,end/16);
requires readable_bytes(io_flags,end/16);
requires writable_bytes(io_work,(end/16)*8);
requires disjoint_bytes(io_flags,end/16,io_work,(end/16)*8);
requires io_owned_queue_word(io_flags,io_work,end/16,used,read)==expected;
requires target>=0 && target<=end-16 && (target&15)==0;
requires readable_bytes(io_code+expected,8);
requires readable_bytes(io_code+(end-16),8);
requires load64(io_code+(end-16))==9;
requires readable_bytes(io_flags+(end-16)/16,1);
requires (load8(io_flags+(end-16)/16)&1)==1;
modifies bytes(io_flags,end/16),bytes(io_work+used*8,16);
ensures result==old(used) || result==old(used)+1 || result==old(used)+2;
ensures load64(io_work+old(read)*8)==expected;
ensures (load8(io_flags+(end-16)/16)&1)==1;
fn io_reach_conditional_with_owned_queue(read,used,end,expected,target) {
    proof {io_worklist_owned_pair(io_flags,io_work,end/16,used,read);}
    let after=io_reach_conditional_with_terminal_return(read,used,end,expected,target);
    return after;
}
