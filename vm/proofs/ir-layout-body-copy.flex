// Selected body copies from layout-map entries following a relocated header.
requires size>=48 && size<=268435456;
requires at>=0 && at<=size-48 && (at&15)==0;
ensures at+16>=0 && at+16<=size-16 && ((at+16)&15)==0;
ensures at+32>=0 && at+32<=size-16 && ((at+32)&15)==0;
ensures at+16!=at+32;
lemma fn io_selected_copy_offsets(at,size) {
    io_selected_body_fits(at,size);
    vm_next_instruction_bounded(at+16,size);
    assert at+32>=0 && at+32<=size-16 && ((at+32)&15)==0;
    assert at+16>=0 && ((at+16)&15)==0;
    assert at+16<at+32;
    assert at+16<=size-16;
    assert at+16!=at+32;
}

requires size>=48 && size<=268435456;
requires at>=0 && at<=size-48 && (at&15)==0;
requires writable_bytes(output,size);
ensures writable_bytes(output+at+16,16);
ensures writable_bytes(output+at+32,16);
ensures readable_bytes(output+at+16,32);
lemma fn io_selected_tail_grants(at,size) {
    io_selected_body_fits(at,size);
    vm_next_instruction_bounded(at+16,size);
    assert (at+16)+16==at+32;
    assert at+32>=0 && at+32<=size-16;
}

requires pc>=0 && pc<=268435440 && (pc&15)==0;
requires readable_bytes(io_code+pc,16);
requires opcode==2 || opcode==9;
requires load64(io_code+pc)==opcode;
requires writable_bytes(output+destination,16);
requires mapped==destination;
modifies bytes(output+destination,16);
ensures result==0;
ensures load64(output+destination)==opcode;
ensures load64(output+destination+8)==old(load64(io_code+pc+8));
fn io_copy_at_map_target(pc,mapped,destination,opcode) {
    return io_write_compacted_instruction(pc,mapped);
}

requires size>=48 && size<=268435456;
requires at>=0 && at<=size-48 && (at&15)==0;
requires push_pc>=0 && push_pc<=268435440 && (push_pc&15)==0;
requires return_pc>push_pc && return_pc<=268435440 && (return_pc&15)==0;
requires readable_bytes(io_code+push_pc,16) && readable_bytes(io_code+return_pc,16);
requires load64(io_code+push_pc)==2 && load64(io_code+return_pc)==9;
requires load64(io_code+push_pc+8)==expected_push;
requires load64(io_code+return_pc+8)==expected_return;
requires writable_bytes(output,size);
requires writable_bytes(output+at+16,16);
requires writable_bytes(output+at+32,16);
requires disjoint_bytes(output+at+16,16,io_code+return_pc,16);
requires readable_bytes(io_map+push_pc/2,8);
requires readable_bytes(io_map+return_pc/2,8);
requires load64(io_map+push_pc/2)==at+16;
requires load64(io_map+return_pc/2)==at+32;
requires disjoint_bytes(output+at+16,16,io_map+return_pc/2,8);
modifies bytes(output+at+16,16),bytes(output+at+32,16);
ensures result==0;
ensures load64(output+at+16)==2;
ensures load64(output+at+24)==expected_push;
ensures load64(output+at+32)==9;
ensures load64(output+at+40)==expected_return;
fn io_copy_selected_push_and_return(push_pc,return_pc,at,size,expected_push,expected_return) {
    proof {
        io_selected_copy_offsets(at,size);
        io_copy_separate_destinations(output,size,at+16,at+32);
    }
    let push_target=io_compacted_offset(push_pc);
    proof {assert push_target==at+16;}
    io_copy_at_map_target(push_pc,push_target,at+16,2);
    proof {
        assert disjoint_bytes(output+at+16,16,io_code+return_pc,16);
        assert readable_bytes(io_code+return_pc,16);
        assert load64(io_code+return_pc)==9;
        assert load64(io_code+return_pc+8)==expected_return;
    }
    proof {
        assert disjoint_bytes(output+at+16,16,io_map+return_pc/2,8);
        assert readable_bytes(io_map+return_pc/2,8);
        assert load64(io_map+return_pc/2)==at+32;
    }
    let return_target=io_compacted_offset(return_pc);
    proof {assert return_target==at+32;}
    io_copy_at_map_target(return_pc,return_target,at+32,9);
    proof {
        assert disjoint_bytes(output+at+16,16,output+at+32,16);
        assert load64(output+at+32)==9;
        assert load64(output+at+40)==expected_return;
        assert load64(output+at+24)==expected_push;
    }
    return 0;
}
