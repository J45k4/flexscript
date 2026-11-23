import "program-state.flex";

global io_code=0;
global io_flags=0;
global io_map=0;

fn io_op(pc) {return load64(io_code+pc);}
fn io_arg(pc) {return load64(io_code+pc+8);}

requires readable_bytes(io_map+pc/2,8);
modifies nothing;
ensures result==load64(io_map+pc/2);
fn io_compacted_offset(pc) {return load64(io_map+pc/2);}

// Copy one live instruction into the compacted stream. Branch targets
// are old PCs and must use the same map as the instruction and function PCs.
requires pc>=0 && pc<=268435440 && (pc&15)==0;
requires readable_bytes(io_code+pc,16);
requires load64(io_code+pc)<10 || load64(io_code+pc)>12 || readable_bytes(io_map+load64(io_code+pc+8)/2,8);
requires writable_bytes(output+at,16);
modifies bytes(output+at,16);
ensures result==0;
ensures load64(output+at)==old(load64(io_code+pc));
ensures old(load64(io_code+pc))>=10 && old(load64(io_code+pc))<=12 || load64(output+at+8)==old(load64(io_code+pc+8));
ensures old(load64(io_code+pc))<10 || old(load64(io_code+pc))>12 || load64(output+at+8)==old(load64(io_map+load64(io_code+pc+8)/2));
fn io_write_compacted_instruction(pc,at) {
    let op=load64(io_code+pc);
    let arg=load64(io_code+pc+8);
    if op>=10 && op<=12 {arg=load64(io_map+arg/2);}
    store64(output+at,op);
    store64(output+at+8,arg);
    return 0;
}

// Use the old entry PC supplied by the function-record loop.
requires writable_bytes(entry,32);
requires readable_bytes(io_map+pc/2,8);
modifies bytes(entry+16,8);
ensures result==0;
ensures load64(entry+16)==old(load64(io_map+pc/2));
ensures load64(entry+24)==old(load64(entry+24));
fn io_relocate_function(entry,pc) {
    store64(entry+16,load64(io_map+pc/2));
    return 0;
}

requires count>=0 && count<=16777216;
requires index>=0 && index<count;
ensures index+1<=count && index<=count-1;
ensures index*8>=0;
ensures index*8<=(count+1)*8-8;
ensures index*16>=0 && index*16<=268435440;
lemma fn io_layout_index(index,count) {
    assert index+1<=count;
    assert index*8+8==(index+1)*8;
    assert (index+1)*8<=(count+1)*8;
    assert (count+1)*8-8==count*8;
    assert index*8<=count*8;
}

requires count>=0 && count<=16777216;
requires index>=0 && index<count;
requires bytes>=0 && bytes<=index*16 && (bytes&15)==0;
ensures bytes<=((index+1)*16) && bytes+16<=((index+1)*16);
ensures bytes+16>=0 && ((bytes+16)&15)==0;
lemma fn io_layout_progress(bytes,index,count) {}

requires count>=0 && count<=16777216;
requires index>=0 && index<=count-1;
requires index*8>=0 && index*8<=(count+1)*8-8;
requires writable_bytes(map,(count+1)*8);
requires readable_bytes(flags,count);
ensures writable_bytes(map+index*8,8);
ensures readable_bytes(flags+index,1);
lemma fn io_layout_region(map,flags,index,count) {}

// The live bit selects a 16-byte increment. The final map word holds
// the compacted size, including when all instructions are dead.
requires count>=0 && count<=16777216;
requires writable_bytes(io_map,(count+1)*8);
requires readable_bytes(io_flags,count);
requires disjoint_bytes(io_map,(count+1)*8,io_flags,count);
modifies bytes(io_map,(count+1)*8);
ensures result>=0 && result<=count*16 && (result&15)==0;
ensures load64(io_map+count*8)==result;
fn io_build_layout(count) {
    let bytes=0;
    let i=0;
    invariant i>=0 && i<=count;
    invariant bytes>=0;
    invariant bytes<=i*16;
    invariant (bytes&15)==0;
    invariant writable_bytes(io_map,(count+1)*8);
    invariant readable_bytes(io_flags,count);
    decreases count-i;
    while i<count {
        proof {
            io_layout_index(i,count);
            io_layout_region(io_map,io_flags,i,count);
            io_layout_progress(bytes,i,count);
        }
        store64(io_map+i*8,bytes);
        let live=load8(io_flags+i)&1;
        proof {assert live==0 || live==1;}
        bytes=bytes+live*16;
        proof {
            assert bytes>=0;
            assert bytes<=(i+1)*16;
            assert (bytes&15)==0;
        }
        i=i+1;
    }
    proof {assert count*8>=0 && count*8+8==(count+1)*8;}
    store64(io_map+count*8,bytes);
    return bytes;
}
