// Production worklist routes with at most one successor.

requires end>=16 && end<=268435456 && (end&15)==0;
requires read>=0 && read<used && used<=end/16;
requires expected>=0 && expected<end && (expected&15)==0;
requires readable_bytes(io_work+read*8,8);
requires load64(io_work+read*8)==expected;
requires readable_bytes(io_code+expected,16);
requires load64(io_code+expected)==opcode;
requires opcode<11 || opcode>12;
requires opcode!=9;
requires opcode!=10 || load64(io_code+expected+8)==target;
requires opcode!=10 || (target>=0 && target<=witness && target<=end && (target&15)==0);
requires opcode==10 || (expected+16>=0 && expected+16<=witness && expected+16<=end);
requires (witness>=0 && witness<end && (witness&15)==0);
requires used<end/16;
requires writable_bytes(io_flags,end/16);
requires readable_bytes(io_flags,end/16);
requires readable_bytes(io_flags+witness/16,1);
requires (load8(io_flags+witness/16)&1)==1;
requires writable_bytes(io_work+used*8,8);
requires disjoint_bytes(io_flags,end/16,io_work+used*8,8);
requires disjoint_bytes(io_flags,end/16,io_work+read*8,8);
requires disjoint_bytes(io_work+used*8,8,io_work+read*8,8);
modifies bytes(io_flags,end/16),bytes(io_work+used*8,8);
ensures result==old(used) || result==old(used)+1;
ensures read==old(read)+1;
ensures load64(io_work+old(read)*8)==expected;
fn io_reach_single_successor_step(read,used,end,expected,opcode,target,witness) {
    ghost let read_entry=read;
    ghost let initial_used=used;
    let pc=load64(io_work+read*8);
    read=read+1;
    proof {
        assert pc==expected;
        assert read==read_entry+1;
    }
    let op=io_op(pc);
    proof {
        assert op==opcode;
        io_worklist_other_opcode(op);
    }
    if op>=10 && op<=12 {
        let destination=io_arg(pc);
        proof {
            assert op==10;
            assert destination==target;
            assert used==initial_used;
        }
        proof {
            assert opcode==10;
            assert destination>=0 && destination<=end && end<=268435456;
            assert (destination&15)==0 && (end&15)==0;
            assert witness>=destination && witness<end && (witness&15)==0;
        }
        ghost let before=used;
        let next=io_enqueue_preserves_observed_flag(destination,end,used,witness,witness);
        proof {
            assert next==before || next==before+1;
            io_worklist_single_append(initial_used,before,next);
            assert disjoint_bytes(io_flags,end/16,io_work+read_entry*8,8);
            assert disjoint_bytes(io_work+initial_used*8,8,io_work+read_entry*8,8);
            assert load64(io_work+read_entry*8)==expected;
        }
        return next;
    }
    if op!=9 && op!=10 {
        proof {
            assert used==initial_used;
            assert ((pc+16)&15)==0;
        }
        proof {
            assert opcode!=9 && opcode!=10;
            assert pc+16>=0 && pc+16<=end && end<=268435456;
            assert ((pc+16)&15)==0 && (end&15)==0;
            assert witness>=pc+16 && witness<end && (witness&15)==0;
        }
        ghost let before=used;
        let next=io_enqueue_preserves_observed_flag(pc+16,end,used,witness,witness);
        proof {
            assert next==before || next==before+1;
            io_worklist_single_append(initial_used,before,next);
            assert disjoint_bytes(io_flags,end/16,io_work+read_entry*8,8);
            assert disjoint_bytes(io_work+initial_used*8,8,io_work+read_entry*8,8);
            assert load64(io_work+read_entry*8)==expected;
        }
        return next;
    }
    proof {assert 0;}
    return used;
}

requires op<11 || op>12;
ensures (op>=10 && op<=12)==(op==10);
lemma fn io_worklist_other_opcode(op) {}

requires before==initial;
requires after==before || after==before+1;
ensures after==initial || after==initial+1;
lemma fn io_worklist_single_append(initial,before,after) {}

// Production return worklist step.
requires end>=16 && end<=268435456 && (end&15)==0;
requires read>=0 && read<used && used<=end/16;
requires expected>=0 && expected<end && (expected&15)==0;
requires readable_bytes(io_work+read*8,8);
requires load64(io_work+read*8)==expected;
requires readable_bytes(io_code+expected,16);
requires load64(io_code+expected)==9;
modifies nothing;
ensures result==used;
ensures read==old(read)+1;
ensures load64(io_work+old(read)*8)==expected;
fn io_reach_return_step(read,used,end,expected) {
    ghost let initial=read;
    let pc=load64(io_work+read*8);
    read=read+1;
    proof {
        assert pc==expected;
        assert read==initial+1;
    }
    let op=io_op(pc);
    proof {assert op==9;}
    if op>=10 && op<=12 {
        used=io_enqueue_preserves_observed_flag(io_arg(pc),end,used,0,0);
    }
    if op!=9 && op!=10 {
        used=io_enqueue_preserves_observed_flag(pc+16,end,used,0,0);
    }
    return used;
}
