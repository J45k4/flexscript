import "../../compiler/ir-layout.flex";
import "../call-frame.flex";

requires a>=0 && a<=268435440 && (a&15)==0;
requires b>=0 && b<=268435440 && (b&15)==0;
requires a<b;
ensures a+16<=b;
lemma fn io_copy_offset_gap(a,b) {
    assert (a>>4)<(b>>4);
    assert ((a>>4)+1)<=(b>>4);
}

requires size>=16 && size<=268435456;
requires at>=0 && at<=size-16;
requires watched>=0 && watched<=size-16;
requires (at&15)==0 && (watched&15)==0 && at!=watched;
requires writable_bytes(base,size);
ensures writable_bytes(base+at,16);
ensures readable_bytes(base+watched,16);
ensures disjoint_bytes(base+at,16,base+watched,16);
lemma fn io_copy_separate_destinations(base,size,at,watched) {
    assert writable_bytes(base+at,16);
    assert writable_bytes(base+watched,16);
    if at<watched {
        io_copy_offset_gap(at,watched);
        assert (base+watched)-(base+at)==watched-at;
        assert watched-at>=16;
    }else {
        io_copy_offset_gap(watched,at);
        assert (base+at)-(base+watched)==at-watched;
        assert at-watched>=16;
    }
}

// This is the preservation step after the selected header has been copied.
requires pc>=0 && pc<=268435440 && (pc&15)==0;
requires readable_bytes(io_code+pc,16);
requires load64(io_code+pc)<10 || load64(io_code+pc)>12 || readable_bytes(io_map+load64(io_code+pc+8)/2,8);
requires size>=16 && size<=268435456;
requires at>=0 && at<=size-16;
requires watched>=0 && watched<=size-16;
requires (at&15)==0 && (watched&15)==0 && at!=watched;
requires writable_bytes(output,size);
modifies bytes(output+at,16);
ensures load64(output+watched)==old(load64(output+watched));
ensures load64(output+watched+8)==old(load64(output+watched+8));
fn optimizer_copy_preserves_other_header(pc,at,watched,size) {
    proof {io_copy_separate_destinations(output,size,at,watched);}
    return io_write_compacted_instruction(pc,at);
}

requires size>=16 && size<=268435456;
requires at>=0 && at<=size-16;
requires writable_bytes(base,size);
ensures writable_bytes(base+at,16);
lemma fn io_copy_destination_grant(base,size,at) {}

requires size>=16 && size<=268435456;
requires at>=0 && at<=size-16;
requires writable_bytes(output,size);
requires disjoint_bytes(output,size,entry,32);
ensures disjoint_bytes(output+at,16,entry+16,8);
ensures disjoint_bytes(output+at,16,entry+24,8);
lemma fn io_copy_record_separate(entry,size,at) {}

requires size>=16 && size<=268435456;
requires at>=0 && at<=size-16;
requires readable_bytes(map_word,8);
requires writable_bytes(output,size);
requires disjoint_bytes(output,size,map_word,8);
ensures disjoint_bytes(output+at,16,map_word,8);
lemma fn io_copy_map_word_separate(size,at,map_word) {}

requires actual==before;
requires before==wanted;
ensures actual==wanted;
lemma fn io_copy_kept_value(actual,before,wanted) {}

requires pc>=0 && pc<=268435440 && (pc&15)==0;
requires compacted_size>=16 && compacted_size<=268435456;
requires at>=0 && at<=compacted_size-16 && (at&15)==0;
requires readable_bytes(io_map+pc/2,8);
requires load64(io_map+pc/2)==at;
requires readable_bytes(io_code+pc,16);
requires load64(io_code+pc)==18 && load64(io_code+pc+8)==slots;
requires writable_bytes(output,compacted_size);
requires writable_bytes(entry,32);
requires load64(entry+16)==pc && load64(entry+24)==arity;
requires disjoint_bytes(output,compacted_size,io_map+pc/2,8);
requires disjoint_bytes(output,compacted_size,entry,32);
modifies bytes(output+at,16);
ensures load64(output+at)==18;
ensures load64(output+at+8)==slots;
ensures load64(io_map+pc/2)==at;
ensures load64(entry+16)==pc;
ensures load64(entry+24)==arity;
ensures disjoint_bytes(output+at,16,entry+16,8);
fn optimizer_writes_observed_header(pc,at,entry,slots,arity,compacted_size) {
    proof {
        io_copy_destination_grant(output,compacted_size,at);
        io_copy_record_separate(entry,compacted_size,at);
        io_copy_map_word_separate(compacted_size,at,io_map+pc/2);
    }
    ghost let saved_map=load64(io_map+pc/2);
    ghost let saved_pc=load64(entry+16);
    ghost let saved_arity=load64(entry+24);
    proof {
        assert saved_map==at;
        assert saved_pc==pc;
        assert saved_arity==arity;
    }
    io_write_compacted_instruction(pc,at);
    proof {
        assert disjoint_bytes(output+at,16,io_map+pc/2,8);
        assert disjoint_bytes(output+at,16,entry+16,8);
        assert disjoint_bytes(output+at,16,entry+24,8);
        assert load64(io_map+pc/2)==saved_map;
        assert load64(entry+16)==saved_pc;
        assert load64(entry+24)==saved_arity;
        io_copy_kept_value(load64(io_map+pc/2),saved_map,at);
        io_copy_kept_value(load64(entry+16),saved_pc,pc);
        io_copy_kept_value(load64(entry+24),saved_arity,arity);
    }
    return 0;
}

requires pc>=0 && pc<=268435440 && (pc&15)==0;
requires compacted_size>=16 && compacted_size<=268435456;
requires at>=0 && at<=compacted_size-16 && (at&15)==0;
requires readable_bytes(io_map+pc/2,8);
requires load64(io_map+pc/2)==at;
requires readable_bytes(io_code+pc,16);
requires load64(io_code+pc)==18 && load64(io_code+pc+8)==slots;
requires writable_bytes(output,compacted_size);
requires writable_bytes(entry,32);
requires load64(entry+16)==pc && load64(entry+24)==arity;
requires disjoint_bytes(output,compacted_size,io_map+pc/2,8);
requires disjoint_bytes(output,compacted_size,entry,32);
modifies bytes(output+at,16),bytes(entry+16,8);
ensures load64(output+at)==18;
ensures load64(output+at+8)==slots;
ensures load64(entry+16)==at;
ensures load64(entry+24)==arity;
ensures result==0;
fn optimizer_copies_and_rebinds_header(pc,at,entry,slots,arity,compacted_size) {
    let dest=io_compacted_offset(pc);
    proof {assert dest==at;}
    optimizer_writes_observed_header(pc,at,entry,slots,arity,compacted_size);
    ghost let header_opcode=load64(output+at);
    ghost let header_slots=load64(output+at+8);
    proof {
        assert header_opcode==18;
        assert header_slots==slots;
    }
    io_relocate_function(entry,pc);
    proof {
        assert disjoint_bytes(output+at,16,entry+16,8);
        assert load64(output+at)==header_opcode;
        assert load64(output+at+8)==header_slots;
        io_copy_kept_value(load64(output+at),header_opcode,18);
        io_copy_kept_value(load64(output+at+8),header_slots,slots);
        assert load64(entry+16)==at;
        assert load64(entry+24)==arity;
    }
    return vm_instruction_outside(load64(entry+16),compacted_size);
}
