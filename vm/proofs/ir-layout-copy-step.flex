// One production compaction-loop iteration for an arbitrary instruction and live bit.
import "../../compiler/ir-layout.flex";

PRODUCTION_LIVE_BIT

requires index>=0 && index<16777216;
ensures (index*16)/16==index;
lemma fn io_copy_flag_index(index) {}

requires index>=0 && index<16777216;
requires pc==index*16;
requires readable_bytes(io_flags+index,1);
modifies nothing;
ensures result==(load8(io_flags+index)&1);
fn io_copy_live_at_index(pc,index) {
    proof {io_copy_flag_index(index);}
    return io_live(pc);
}

requires index>=0 && index<16777216;
requires pc==index*16;
requires readable_bytes(io_flags+index,1);
requires readable_bytes(io_map+pc/2,8);
requires load64(io_map+pc/2)==at;
requires readable_bytes(io_code+pc,16);
requires (load8(io_flags+index)&1)==0 || load64(io_code+pc)<10 || load64(io_code+pc)>12 || readable_bytes(io_map+load64(io_code+pc+8)/2,8);
requires (load8(io_flags+index)&1)==0 || load64(io_code+pc)<10 || load64(io_code+pc)>12 || load64(io_map+load64(io_code+pc+8)/2)==branch_target;
requires writable_bytes(output+at,16);
modifies bytes(output+at,16);
ensures (old(load8(io_flags+index))&1)!=0 || load64(output+at)==old(load64(output+at));
ensures (old(load8(io_flags+index))&1)!=0 || load64(output+at+8)==old(load64(output+at+8));
ensures (old(load8(io_flags+index))&1)==0 || load64(output+at)==old(load64(io_code+pc));
ensures (old(load8(io_flags+index))&1)==0 || (old(load64(io_code+pc))>=10 && old(load64(io_code+pc))<=12) || load64(output+at+8)==old(load64(io_code+pc+8));
ensures (old(load8(io_flags+index))&1)==0 || old(load64(io_code+pc))<10 || old(load64(io_code+pc))>12 || load64(output+at+8)==branch_target;
fn io_copy_loop_step(index,pc,at,branch_target) {
    proof {
        io_copy_flag_index(index);
        assert pc>=0 && pc<=268435440 && (pc&15)==0;
    }
    let live=io_copy_live_at_index(pc,index);
    if live {
        proof {
            assert (load8(io_flags+index)&1)==1;
            assert load64(io_code+pc)<10 || load64(io_code+pc)>12 || readable_bytes(io_map+load64(io_code+pc+8)/2,8);
        }
        let destination=io_compacted_offset(pc);
        proof {assert destination==at;}
        ghost let opcode=load64(io_code+pc);
        proof {
            assert opcode<10 || opcode>12 || load64(io_map+load64(io_code+pc+8)/2)==branch_target;
        }
        io_write_compacted_instruction(pc,destination);
    }
    return 0;
}
