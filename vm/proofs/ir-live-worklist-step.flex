// Production conditional worklist step with two possible insertions.

requires end>=32 && end<=268435456 && (end&15)==0;
requires read>=0 && read<used && used<=end/16-2;
requires expected>=0 && expected<=end-32 && (expected&15)==0;
requires expected>=0 && expected<end;
requires target>=0 && target<=branch_live && branch_live<end;
requires target>=0 && target<=end;
requires (target&15)==0 && (branch_live&15)==0;
requires fall_live>=expected+16 && fall_live<end && (fall_live&15)==0;
requires readable_bytes(io_work+read*8,8);
requires load64(io_work+read*8)==expected;
requires readable_bytes(io_code+expected,16);
requires load64(io_code+expected)==11 || load64(io_code+expected)==12;
requires load64(io_code+expected+8)==target;
requires writable_bytes(io_flags,end/16);
requires readable_bytes(io_flags,end/16);
requires readable_bytes(io_flags+branch_live/16,1);
requires readable_bytes(io_flags+fall_live/16,1);
requires (load8(io_flags+branch_live/16)&1)==1;
requires (load8(io_flags+fall_live/16)&1)==1;
requires writable_bytes(io_work+used*8,16);
requires disjoint_bytes(io_flags,end/16,io_work+used*8,16);
requires disjoint_bytes(io_flags,end/16,io_work+read*8,8);
requires disjoint_bytes(io_work+used*8,16,io_work+read*8,8);
modifies bytes(io_flags,end/16),bytes(io_work+used*8,16);
ensures result==old(used) || result==old(used)+1 || result==old(used)+2;
ensures read==old(read)+1;
ensures load64(io_work+old(read)*8)==expected;
ensures (load8(io_flags+fall_live/16)&1)==1;
fn io_reach_conditional_step(read,used,end,expected,target,branch_live,fall_live) {
    ghost let read_entry=read;
    ghost let initial_used=used;
    ghost let initial_fall=load8(io_flags+fall_live/16);
    let pc=load64(io_work+read*8);
    read=read+1;
    proof {
        assert pc==expected;
        assert read==read_entry+1;
    }
    let op=io_op(pc);
    proof {
        assert op==11 || op==12;
        io_worklist_is_conditional(op);
        io_next_bounded_step(pc,end);
        io_worklist_slot_grant(initial_used,used,read_entry,end);
    }
    if op>=10 && op<=12 {
        let destination=io_arg(pc);
        proof {
            assert destination==target;
            assert destination>=0 && destination<=end;
            assert (destination&15)==0 && (end&15)==0;
            assert branch_live>=destination && branch_live<end && (branch_live&15)==0;
            assert readable_bytes(io_flags+fall_live/16,1);
        }
        used=io_enqueue_preserves_observed_flag(destination,end,used,branch_live,fall_live);
        proof {
            assert used==initial_used || used==initial_used+1;
            assert disjoint_bytes(io_flags,end/16,io_work+read_entry*8,8);
            assert disjoint_bytes(io_work+initial_used*8,8,io_work+read_entry*8,8);
            assert load64(io_work+read_entry*8)==expected;
            assert (load8(io_flags+fall_live/16)&251)==(initial_fall&251);
            io_worklist_keeps_live(initial_fall,load8(io_flags+fall_live/16));
        }
    }
    if op!=9 && op!=10 {
        proof {
            assert used==initial_used || used==initial_used+1;
            io_worklist_slot_grant(initial_used,used,read_entry,end);
            assert (load8(io_flags+fall_live/16)&1)==1;
            assert pc+16>=0 && pc+16<=end;
            assert ((pc+16)&15)==0 && (end&15)==0;
            assert fall_live>=pc+16 && fall_live<end && (fall_live&15)==0;
        }
        ghost let used_before_fall=used;
        used=io_enqueue_preserves_observed_flag(pc+16,end,used,fall_live,fall_live);
        proof {
            assert used==used_before_fall || used==used_before_fall+1;
            assert disjoint_bytes(io_flags,end/16,io_work+read_entry*8,8);
            assert disjoint_bytes(io_work+used_before_fall*8,8,io_work+read_entry*8,8);
            assert load64(io_work+read_entry*8)==expected;
            io_worklist_two_append_bound(initial_used,used_before_fall,used);
            assert read==read_entry+1;
        }
        return used;
    }
    proof {assert 0;}
    return used;
}

requires end>=32 && end<=268435456 && (end&15)==0;
requires initial>=0 && initial<=end/16-2;
requires selected==initial || selected==initial+1;
requires previous>=0 && previous<initial;
requires writable_bytes(io_work+initial*8,16);
requires disjoint_bytes(io_flags,end/16,io_work+initial*8,16);
requires disjoint_bytes(io_work+initial*8,16,io_work+previous*8,8);
ensures selected>=0 && selected<end/16;
ensures writable_bytes(io_work+selected*8,8);
ensures disjoint_bytes(io_flags,end/16,io_work+selected*8,8);
ensures disjoint_bytes(io_work+selected*8,8,io_work+previous*8,8);
lemma fn io_worklist_slot_grant(initial,selected,previous,end) {
    io_worklist_adjacent_grants(io_work+initial*8,io_flags,end/16,io_work+previous*8);
    if selected==initial {
        assert io_work+selected*8==io_work+initial*8;
        io_worklist_alias_grants(io_work+initial*8,io_work+selected*8,io_flags,end/16,io_work+previous*8);
    }else {
        assert selected==initial+1;
        io_worklist_word_stride(initial,selected);
        io_worklist_offset_alias(io_work,selected*8,initial*8+8);
        io_worklist_alias_grants(io_work+initial*8+8,io_work+selected*8,io_flags,end/16,io_work+previous*8);
    }
}

requires (initial&1)==1;
requires (later&251)==(initial&251);
ensures (later&1)==1;
lemma fn io_worklist_keeps_live(initial,later) {}

requires op==11 || op==12;
ensures op>=10 && op<=12;
ensures op!=9 && op!=10;
lemma fn io_worklist_is_conditional(op) {}

requires initial>=0 && initial<=16777214;
requires before==initial || before==initial+1;
requires after==before || after==before+1;
ensures after==initial || after==initial+1 || after==initial+2;
lemma fn io_worklist_two_append_bound(initial,before,after) {}

requires selected==initial+1;
ensures selected*8==initial*8+8;
lemma fn io_worklist_word_stride(initial,selected) {}

requires writable_bytes(pair,16);
requires disjoint_bytes(flags,capacity,pair,16);
requires disjoint_bytes(pair,16,previous,8);
ensures writable_bytes(pair,8);
ensures writable_bytes(pair+8,8);
ensures disjoint_bytes(flags,capacity,pair,8);
ensures disjoint_bytes(flags,capacity,pair+8,8);
ensures disjoint_bytes(pair,8,previous,8);
ensures disjoint_bytes(pair+8,8,previous,8);
lemma fn io_worklist_adjacent_grants(pair,flags,capacity,previous) {}

requires offset==expected;
ensures base+offset==base+expected;
lemma fn io_worklist_offset_alias(base,offset,expected) {}

requires from==to;
requires writable_bytes(from,8);
requires disjoint_bytes(flags,capacity,from,8);
requires disjoint_bytes(from,8,previous,8);
ensures writable_bytes(to,8);
ensures disjoint_bytes(flags,capacity,to,8);
ensures disjoint_bytes(to,8,previous,8);
lemma fn io_worklist_alias_grants(from,to,flags,capacity,previous) {}
