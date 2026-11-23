// Live successor witnesses derived from a final return.

requires end>=16 && end<=268435456 && (end&15)==0;
requires pc>=0 && pc<=end-16 && (pc&15)==0;
requires opcode!=9;
requires readable_bytes(io_code+pc,8);
requires load64(io_code+pc)==opcode;
requires readable_bytes(io_code+(end-16),8);
requires load64(io_code+(end-16))==9;
requires readable_bytes(io_flags+(end-16)/16,1);
requires (load8(io_flags+(end-16)/16)&1)==1;
modifies nothing;
ensures pc+16>=0 && pc+16<=end-16;
ensures ((end-16)&15)==0;
ensures readable_bytes(io_flags+(end-16)/16,1);
ensures (load8(io_flags+(end-16)/16)&1)==1;
lemma fn io_terminal_return_witness(pc,end,opcode) {
    let last=end-16;
    let current=load64(io_code+pc);
    let final_opcode=load64(io_code+last);
    proof {
        assert current==opcode;
        assert final_opcode==9;
        if pc==last {
            io_terminal_add_equal(io_code,pc,last);
            io_terminal_same_word(io_code+pc,io_code+last);
            assert current==final_opcode;
        }
        assert pc<last;
        assert (last&15)==0;
        io_next_bounded_step(pc,last);
        assert pc+16>=pc;
        assert pc+16<=last;
    }
}

requires a==b;
requires readable_bytes(a,8);
requires readable_bytes(b,8);
ensures load64(a)==load64(b);
lemma fn io_terminal_same_word(a,b) {}

requires left==right;
ensures base+left==base+right;
lemma fn io_terminal_add_equal(base,left,right) {}

requires expected>=0 && expected<=end-16;
requires end>=32 && end<=268435456;
requires (expected&15)==0 && (end&15)==0;
requires expected+16<=end-16;
ensures expected<=end-32;
lemma fn io_terminal_window_limit(expected,end) {
    assert ((expected+16)>>4)==(expected>>4)+1;
    assert ((end-16)>>4)==(end>>4)-1;
    assert (expected>>4)<=(end>>4)-2;
    assert ((end-32)>>4)==(end>>4)-2;
}

requires end>=32 && end<=268435456 && (end&15)==0;
requires read>=0 && read<used && used<=end/16-2;
requires expected>=0 && expected<=end-16 && (expected&15)==0;
requires expected>=0 && expected<end;
requires target>=0 && target<=end;
requires readable_bytes(io_work+read*8,8);
requires load64(io_work+read*8)==expected;
requires readable_bytes(io_code+expected,16);
requires load64(io_code+expected)==11 || load64(io_code+expected)==12;
requires load64(io_code+expected+8)==target;
requires writable_bytes(io_flags,end/16);
requires readable_bytes(io_flags,end/16);
requires writable_bytes(io_work+used*8,16);
requires disjoint_bytes(io_flags,end/16,io_work+used*8,16);
requires disjoint_bytes(io_flags,end/16,io_work+read*8,8);
requires disjoint_bytes(io_work+used*8,16,io_work+read*8,8);
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
fn io_reach_conditional_with_terminal_return(read,used,end,expected,target) {
    let witness=end-16;
    proof {
        let opcode=load64(io_code+expected);
        assert opcode==11 || opcode==12;
        assert opcode!=9;
        io_terminal_return_witness(expected,end,opcode);
        assert witness==end-16;
        assert expected+16<=witness;
        io_terminal_window_limit(expected,end);
        assert target<=witness && witness<end;
    }
    let after=io_reach_conditional_step(read,used,end,expected,target,witness,witness);
    return after;
}
