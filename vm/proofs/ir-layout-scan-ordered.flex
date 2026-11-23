// Carry the ordered instruction copies through function-record relocation.
ORDERED_SCAN_REQUIREMENTS
requires writable_bytes(entry,32);
requires load64(entry+16)==first*16 && load64(entry+24)==arity;
requires disjoint_bytes(io_map,(count+1)*8,entry,32);
requires disjoint_bytes(output,count*16,entry,32);
modifies bytes(io_map,(count+1)*8),bytes(output,count*16),bytes(entry+16,8);
ensures load64(output+result)==18;
ensures load64(output+result+8)==old(load64(io_code+first*16+8));
ensures load64(output+result+16)==2;
ensures load64(output+result+24)==old(load64(io_code+first*16+24));
ensures load64(output+result+32)==9;
ensures load64(output+result+40)==old(load64(io_code+first*16+40));
ensures load64(entry+16)==result;
ensures load64(entry+24)==arity;
ensures result>=0 && (result&15)==0 && result<=load64(io_map+count*8)-48;
fn io_scan_copy_ordered_then_relocate(count,first,entry,arity) {
    let pc=first*16;
    proof {
        io_layout_triple_indices(first,count);
        io_layout_pc_slot(first);
        io_record_words_separate(io_map,(count+1)*8,entry);
        io_record_words_separate(output,count*16,entry);
    }
    ghost let original_slots=load64(io_code+pc+8);
    ghost let original_push=load64(io_code+pc+24);
    ghost let original_return=load64(io_code+pc+40);
    ghost let prior_pc=load64(entry+16);
    ghost let prior_arity=load64(entry+24);
    proof {
        assert prior_pc==pc;
        assert prior_arity==arity;
    }
    let at=io_scan_then_copy_ordered(count,first);
    proof {
        assert disjoint_bytes(io_map,(count+1)*8,entry+16,8);
        assert disjoint_bytes(output,count*16,entry+16,8);
        assert disjoint_bytes(io_map,(count+1)*8,entry+24,8);
        assert disjoint_bytes(output,count*16,entry+24,8);
    }
    let source_pc=load64(entry+16);
    proof {
        assert source_pc==prior_pc;
        assert source_pc==pc;
        assert load64(io_map+pc/2)==at;
        assert load64(entry+24)==prior_arity;
        io_rebind_watched_spans(count,at,entry);
        assert disjoint_bytes(output+at,16,entry+16,8);
        assert disjoint_bytes(output+at+16,16,entry+16,8);
        assert disjoint_bytes(output+at+32,16,entry+16,8);
        assert disjoint_bytes(io_map+count*8,8,entry+16,8);
    }
    io_relocate_expected_record(entry,pc,at,arity);
    proof {
        assert disjoint_bytes(output+at,16,entry+16,8);
        assert disjoint_bytes(output+at+16,16,entry+16,8);
        assert disjoint_bytes(output+at+32,16,entry+16,8);
        assert load64(output+at+8)==original_slots;
        assert load64(output+at+24)==original_push;
        assert load64(output+at+40)==original_return;
    }
    return at;
}

// Derive the selected header and body copies from the production layout scan.
LIVE_TRIPLE_REQUIREMENTS
requires readable_bytes(io_code+first*16,48);
requires load64(io_code+first*16)==18;
requires load64(io_code+(first+1)*16)==2 && load64(io_code+(first+1)*16+16)==9;
requires writable_bytes(output,count*16);
requires disjoint_bytes(output,count*16,io_map,(count+1)*8);
requires disjoint_bytes(output,count*16,io_code+first*16,48);
requires disjoint_bytes(io_map,(count+1)*8,io_code+first*16,48);
modifies bytes(io_map,(count+1)*8),bytes(output,count*16);
ensures result==load64(io_map+(first*16)/2);
ensures result<=count*16-48;
ensures result>=0 && (result&15)==0 && result<=load64(io_map+count*8)-48;
ensures load64(output+result)==18;
ensures load64(output+result+8)==old(load64(io_code+first*16+8));
ensures load64(output+result+16)==2;
ensures load64(output+result+24)==old(load64(io_code+first*16+24));
ensures load64(output+result+32)==9;
ensures load64(output+result+40)==old(load64(io_code+first*16+40));
fn io_scan_then_copy_ordered(count,first) {
    let pc=first*16;
    let capacity=count*16;
    proof {
        io_layout_triple_indices(first,count);
        io_layout_copy_source_positions(first,count);
        io_layout_ordered_word_indices(first,count);
    }
    ghost let original_slots=load64(io_code+pc+8);
    ghost let original_push=load64(io_code+pc+24);
    ghost let original_return=load64(io_code+pc+40);
    let size=io_build_layout_live_triple(count,first);
    let at=load64(io_map+first*8);
    ghost let push_slot=load64(io_map+(first+1)*8);
    ghost let return_slot=load64(io_map+(first+2)*8);
    proof {
        assert size==load64(io_map+count*8);
        assert at>=0 && at<=size-48;
        assert size<=capacity;
        io_layout_bound_through_capacity(at,size,capacity);
        io_layout_accessor_word(io_map,first);
        io_layout_adjacent_accessor_word(io_map,first);
        io_layout_adjacent_accessor_word(io_map,first+1);
        assert (pc+32)==(first+1)*16+16;
        io_layout_map_value_link(push_slot,load64(io_map+(pc+16)/2),at,16);
        io_layout_map_value_link(return_slot,load64(io_map+(pc+32)/2),at,32);
        assert disjoint_bytes(io_map,(count+1)*8,io_code+pc,48);
        assert load64(io_code+pc)==18;
        assert load64(io_code+pc+16)==2;
        assert load64(io_code+pc+32)==9;
        io_layout_ordered_destination_spans(count,first,at);
        io_layout_header_map_separate(first,count);
    }
    let slots=load64(io_code+pc+8);
    let push_arg=load64(io_code+pc+24);
    let return_arg=load64(io_code+pc+40);
    proof {
        assert slots==original_slots;
        assert push_arg==original_push;
        assert return_arg==original_return;
    }
    io_copy_ordered_in_buffer(pc,at,slots,push_arg,return_arg,capacity);
    proof {
        assert disjoint_bytes(output,capacity,io_map+count*8,8);
        assert disjoint_bytes(output,capacity,io_map+first*8,8);
        assert load64(io_map+count*8)==size;
        assert load64(io_map+first*8)==at;
        io_layout_accessor_word(io_map,first);
    }
    return at;
}

// Ordered copy wrapper and span lemmas.
ORDERED_COPY_REQUIREMENTS
requires capacity>=48 && capacity<=268435456;
requires at<=capacity-48;
requires writable_bytes(output,capacity);
modifies bytes(output,capacity);
ORDERED_COPY_RESULTS
fn io_copy_ordered_in_buffer(pc,at,slots,push_arg,return_arg,capacity) {
    proof {published_body_offsets(at,capacity);}
    return io_copy_selected_header_and_body(pc,at,slots,push_arg,return_arg);
}

requires span>=48 && span<=268435456;
requires at>=0 && at<=span-48;
ensures at+16>=0 && at+16<=span-32;
lemma fn published_body_offsets(at,span) {
    assert at<=268435408;
    assert at+16>=0;
    assert (span-48)+16==span-32;
    assert at+16<=(span-48)+16;
}
requires count>=3 && count<=16777216;
requires first>=0 && first<=count-3;
ensures first*16>=0 && first*16<=268435408 && ((first*16)&15)==0;
ensures first*16+16==(first+1)*16;
ensures first*16+32==(first+1)*16+16;
lemma fn io_layout_ordered_word_indices(first,count) {
    io_layout_triple_indices(first,count);
}

requires count>=3 && count<=16777216;
requires first>=0 && first<=count-3;
requires at>=0 && at<=count*16-48 && (at&15)==0;
requires writable_bytes(output,count*16);
requires disjoint_bytes(output,count*16,io_code+first*16,48);
requires disjoint_bytes(output,count*16,io_map,(count+1)*8);
ensures writable_bytes(output+at,48);
ensures writable_bytes(output+at,16);
ensures writable_bytes(output+at+16,16);
ensures writable_bytes(output+at+32,16);
ensures disjoint_bytes(output+at,48,io_code+first*16,48);
ensures disjoint_bytes(output+at,48,io_map+(first*16)/2,8);
ensures disjoint_bytes(output+at,48,io_map+(first*16+16)/2,8);
ensures disjoint_bytes(output+at,48,io_map+(first*16+32)/2,8);
ensures disjoint_bytes(output+at,16,io_code+first*16+16,16);
ensures disjoint_bytes(output+at,16,io_code+first*16+32,16);
ensures disjoint_bytes(output+at+16,16,io_code+first*16+32,16);
ensures disjoint_bytes(output+at,16,io_map+(first*16+16)/2,8);
ensures disjoint_bytes(output+at,16,io_map+(first*16+32)/2,8);
ensures disjoint_bytes(output+at+16,16,io_map+(first*16+32)/2,8);
ensures disjoint_bytes(output+at,16,output+at+16,16);
ensures disjoint_bytes(output+at,16,output+at+32,16);
ensures disjoint_bytes(output+at+16,16,output+at+32,16);
ensures disjoint_bytes(output,count*16,io_map+count*8,8);
lemma fn io_layout_ordered_destination_spans(count,first,at) {
    io_layout_triple_indices(first,count);
    io_layout_ordered_word_indices(first,count);
    io_layout_selected_memory_geometry(at,first,count);
    published_body_offsets(at,count*16);
    io_copy_separate_destinations(output,count*16,at,at+16);
    io_copy_separate_destinations(output,count*16,at,at+32);
    io_copy_separate_destinations(output,count*16,at+16,at+32);
    io_layout_pc_slot(first);
    io_layout_next_pc_slot(first);
    io_layout_next_pc_slot(first+1);
}
