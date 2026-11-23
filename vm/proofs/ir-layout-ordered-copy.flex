// Copy the selected live header, PUSH, and RETURN in increasing source-PC order.
import "../../compiler/ir-layout.flex";

requires pc>=0 && pc<=268435440 && (pc&15)==0;
requires readable_bytes(io_code+pc,16);
requires opcode==18 || opcode==2 || opcode==9;
requires load64(io_code+pc)==opcode;
requires load64(io_code+pc+8)==operand;
requires writable_bytes(output+at,16);
requires mapped==at;
modifies bytes(output+at,16);
ensures result==0;
ensures load64(output+at)==opcode;
ensures load64(output+at+8)==operand;
fn io_copy_typed(pc,mapped,at,opcode,operand) {
    return io_write_compacted_instruction(pc,mapped);
}

requires pc>=0 && pc<=268435408 && (pc&15)==0;
requires at>=0 && at<=268435408 && (at&15)==0;
requires readable_bytes(io_code+pc,48);
requires load64(io_code+pc)==18 && load64(io_code+pc+8)==slots;
requires load64(io_code+pc+16)==2 && load64(io_code+pc+24)==push_arg;
requires load64(io_code+pc+32)==9 && load64(io_code+pc+40)==return_arg;
requires readable_bytes(io_map+pc/2,8);
requires readable_bytes(io_map+(pc+16)/2,8);
requires readable_bytes(io_map+(pc+32)/2,8);
requires load64(io_map+pc/2)==at;
requires load64(io_map+(pc+16)/2)==at+16;
requires load64(io_map+(pc+32)/2)==at+32;
requires writable_bytes(output+at,48);
requires disjoint_bytes(output+at,48,io_code+pc,48);
requires disjoint_bytes(output+at,48,io_map+pc/2,8);
requires disjoint_bytes(output+at,48,io_map+(pc+16)/2,8);
requires disjoint_bytes(output+at,48,io_map+(pc+32)/2,8);
requires readable_bytes(io_code+pc,16);
requires readable_bytes(io_code+pc+16,16);
requires readable_bytes(io_code+pc+32,16);
requires writable_bytes(output+at,16);
requires writable_bytes(output+at+16,16);
requires writable_bytes(output+at+32,16);
requires disjoint_bytes(output+at,16,io_code+pc+16,16);
requires disjoint_bytes(output+at,16,io_code+pc+32,16);
requires disjoint_bytes(output+at+16,16,io_code+pc+32,16);
requires disjoint_bytes(output+at,16,io_map+(pc+16)/2,8);
requires disjoint_bytes(output+at,16,io_map+(pc+32)/2,8);
requires disjoint_bytes(output+at+16,16,io_map+(pc+32)/2,8);
requires disjoint_bytes(output+at,16,output+at+16,16);
requires disjoint_bytes(output+at,16,output+at+32,16);
requires disjoint_bytes(output+at+16,16,output+at+32,16);
modifies bytes(output+at,48);
ensures result==0;
ensures load64(output+at)==18;
ensures load64(output+at+8)==slots;
ensures load64(output+at+16)==2;
ensures load64(output+at+24)==push_arg;
ensures load64(output+at+32)==9;
ensures load64(output+at+40)==return_arg;
fn io_copy_selected_header_and_body(pc,at,slots,push_arg,return_arg) {
    let push_pc=pc+16;
    let return_pc=pc+32;
    let header_at=io_compacted_offset(pc);
    io_copy_typed(pc,header_at,at,18,slots);
    proof {
        assert disjoint_bytes(output+at,16,io_code+push_pc,16);
        assert disjoint_bytes(output+at,16,io_code+return_pc,16);
        assert disjoint_bytes(output+at,16,io_map+push_pc/2,8);
        assert disjoint_bytes(output+at,16,io_map+return_pc/2,8);
    }
    let push_at=io_compacted_offset(push_pc);
    let saved_push=load64(io_code+push_pc+8);
    proof {assert saved_push==push_arg;}
    io_copy_typed(push_pc,push_at,at+16,2,saved_push);
    proof {
        assert disjoint_bytes(output+at+16,16,io_code+return_pc,16);
        assert disjoint_bytes(output+at+16,16,io_map+return_pc/2,8);
    }
    let return_at=io_compacted_offset(return_pc);
    let saved_return=load64(io_code+return_pc+8);
    proof {assert saved_return==return_arg;}
    io_copy_typed(return_pc,return_at,at+32,9,saved_return);
    proof {
        assert disjoint_bytes(output+at,16,output+at+16,16);
        assert disjoint_bytes(output+at,16,output+at+32,16);
        assert disjoint_bytes(output+at+16,16,output+at+32,16);
    }
    return 0;
}
