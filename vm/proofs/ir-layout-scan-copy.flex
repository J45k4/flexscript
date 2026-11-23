// Compose the production layout scan with the two selected body writes.
requires count>=3 && count<=16777216;
requires first>=0 && first<=count-3;
requires writable_bytes(io_map,(count+1)*8);
requires readable_bytes(io_flags,count);
requires disjoint_bytes(io_map,(count+1)*8,io_flags,count);
requires readable_bytes(io_map+(first)*8,8);
requires readable_bytes(io_flags+(first),1);
requires (load8(io_flags+(first))&1)==1;
requires readable_bytes(io_map+(first+1)*8,8);
requires readable_bytes(io_flags+(first+1),1);
requires (load8(io_flags+(first+1))&1)==1;
requires readable_bytes(io_map+(first+2)*8,8);
requires readable_bytes(io_flags+(first+2),1);
requires (load8(io_flags+(first+2))&1)==1;

requires readable_bytes(io_code+(first+1)*16,32);
requires load64(io_code+(first+1)*16)==2 && load64(io_code+(first+1)*16+16)==9;
requires writable_bytes(output,count*16);
requires disjoint_bytes(output,count*16,io_map,(count+1)*8);
requires disjoint_bytes(output,count*16,io_code+(first+1)*16,32);
requires disjoint_bytes(io_map,(count+1)*8,io_code+(first+1)*16,32);
modifies bytes(io_map,(count+1)*8),bytes(output,count*16);
ensures result==load64(io_map+(first*16)/2);
ensures load64(output+result+16)==2;
ensures load64(output+result+24)==old(load64(io_code+(first+1)*16+8));
ensures load64(output+result+32)==9;
ensures load64(output+result+40)==old(load64(io_code+(first+1)*16+24));
ensures result>=0;
ensures (result&15)==0;
ensures result<=load64(io_map+count*8)-48;
ensures result<=count*16-48;
ensures load64(io_map+count*8)>=48;
ensures load64(io_map+count*8)<=count*16;
ensures (load64(io_map+count*8)&15)==0;
fn io_build_layout_then_copy_selected_body(count,first) {
    let push_pc=(first+1)*16;
    let return_pc=push_pc+16;
    ghost let original_push=load64(io_code+push_pc+8);
    ghost let original_return=load64(io_code+return_pc+8);
    let size=io_build_layout_live_triple(count,first);
    let at=load64(io_map+first*8);
    ghost let push_at=load64(io_map+(first+1)*8);
    ghost let return_at=load64(io_map+(first+2)*8);
    proof {
        io_layout_triple_indices(first,count);
        io_layout_copy_source_positions(first,count);
        assert at>=0 && at<=size-48;
        assert load64(io_map+count*8)==size;
        assert size>=0;
        assert size<=count*16;
        io_layout_bound_through_capacity(at,size,count*16);
        io_selected_tail_grants(at,count*16);
        io_layout_copy_destinations_separate(at,first,count);
        io_layout_selected_memory_geometry(at,first,count);
        assert readable_bytes(io_map+(first+1)*8,8);
        assert readable_bytes(io_map+(first+2)*8,8);
        assert push_at==at+16;
        assert return_at==at+32;
        io_layout_accessor_word(io_map,first+1);
        io_layout_adjacent_accessor_word(io_map,first+1);
        io_layout_map_value_link(push_at,load64(io_map+push_pc/2),at,16);
        io_layout_map_value_link(return_at,load64(io_map+return_pc/2),at,32);
        assert disjoint_bytes(io_map,(count+1)*8,io_code+push_pc,32);
        assert readable_bytes(io_code+push_pc,16);
        assert readable_bytes(io_code+return_pc,16);
        assert load64(io_code+push_pc)==2;
        assert load64(io_code+return_pc)==9;
        assert load64(io_map+count*8)==size;
    }
    let push_arg=load64(io_code+push_pc+8);
    let return_arg=load64(io_code+return_pc+8);
    proof {
        assert push_arg==original_push;
        assert return_arg==original_return;
    }
    let size_word=io_map+count*8;
    proof {
        assert disjoint_bytes(output,count*16,size_word,8);
        assert readable_bytes(size_word,8);
        assert load64(size_word)==size;
        assert size>=48 && size<=count*16 && (size&15)==0;
    }
    io_copy_in_output_buffer(push_pc,return_pc,at,count*16,push_arg,return_arg,(count+1)*8,size_word,size);
    proof {
        assert load64(output+at+24)==push_arg;
        assert load64(output+at+40)==return_arg;
        assert disjoint_bytes(output,count*16,io_map+count*8,8);
        assert load64(io_map+count*8)==size;
        io_layout_header_map_separate(first,count);
        assert load64(io_map+first*8)==at;
        io_layout_accessor_word(io_map,first);
        assert load64(io_map+(first*16)/2)==at;
    }
    return at;
}

LAYOUT_OBSERVER_PROOF
LAYOUT_PC_SLOT_PROOF
requires index>=0 && index<16777216;
requires readable_bytes(map+index*8,8);
ensures readable_bytes(map+(index*16)/2,8);
ensures load64(map+(index*16)/2)==load64(map+index*8);
lemma fn io_layout_accessor_word(map,index) {
    io_layout_pc_slot(index);
    assert map+(index*16)/2==map+index*8;
    io_layout_same_word(map+index*8,map+(index*16)/2);
}

BODY_COPY_PROOF
requires count>=3 && count<=16777216;
requires first>=0 && first<=count-3;
requires at>=0 && at<=count*16-48 && (at&15)==0;
requires disjoint_bytes(output,count*16,io_map,(count+1)*8);
requires disjoint_bytes(output,count*16,io_code+(first+1)*16,32);
ensures disjoint_bytes(output+at+16,16,io_map+(((first+1)*16)+16)/2,8);
ensures disjoint_bytes(output,count*16,io_map+count*8,8);
ensures disjoint_bytes(output+at+16,16,io_code+(first+1)*16+16,16);
lemma fn io_layout_copy_destinations_separate(at,first,count) {
    io_layout_triple_indices(first,count);
    io_layout_selected_memory_geometry(at,first,count);
    io_layout_next_pc_slot(first+1);
    let return_word=((first+1)*16+16)/2;
    let expected_word=(first+2)*8;
    assert return_word==expected_word;
    assert expected_word>=0 && expected_word<=(count+1)*8-8;
    assert disjoint_bytes(output+at+16,16,io_map,(count+1)*8);
    io_layout_disjoint_map_slice(output+at+16,io_map,(count+1)*8,expected_word);
    io_layout_disjoint_map_delta(output+at+16,io_map,expected_word,return_word);
}

requires count>=3 && count<=16777216;
requires first>=0 && first<=count-3;
requires at>=0 && at<=count*16-48 && (at&15)==0;
ensures at+16>=0 && at+16<=count*16-32;
ensures at+16>=0 && at+16<=count*16-16;
ensures at+32>=0 && at+32<=count*16-16;
ensures (first+2)*8>=0 && (first+2)*8<=count*8;
ensures count*8==(count+1)*8-8;
ensures (first+2)*16==(first+1)*16+16;
lemma fn io_layout_selected_memory_geometry(at,first,count) {
    io_layout_triple_indices(first,count);
    assert count*16>=48 && count*16<=268435456;
    io_selected_body_fits(at,count*16);
    vm_next_instruction_bounded(at+16,count*16);
    assert at+16+16==at+32;
    assert (first+2)*8<=count*8;
    assert (first+2)*16==(first+1)*16+16;
}




requires size>=8 && size<=134217736;
requires offset>=0 && offset<=size-8;
requires disjoint_bytes(dst,16,map,size);
ensures disjoint_bytes(dst,16,map+offset,8);
lemma fn io_layout_disjoint_map_slice(dst,map,size,offset) {}

requires expected==actual;
requires disjoint_bytes(dst,16,map+expected,8);
ensures disjoint_bytes(dst,16,map+actual,8);
lemma fn io_layout_disjoint_map_delta(dst,map,expected,actual) {}

requires size>=0 && size<=capacity && capacity<=268435456;
requires at>=0 && at<=size-48;
ensures size>=48;
ensures at<=capacity-48;
lemma fn io_layout_bound_through_capacity(at,size,capacity) {
    assert size>=48;
    assert at+48<=size;
    assert at+48<=capacity;
}

requires observed==mapped;
requires observed==base+delta;
ensures mapped==base+delta;
lemma fn io_layout_map_value_link(observed,mapped,base,delta) {}

requires count>=3 && count<=16777216;
requires first>=0 && first<=count-3;
ensures (first+1)*16>=0 && (first+1)*16<=268435440 && (((first+1)*16)&15)==0;
ensures (first+2)*16>(first+1)*16 && (first+2)*16<=268435440 && (((first+2)*16)&15)==0;
ensures count*16>=48 && count*16<=268435456;
lemma fn io_layout_copy_source_positions(first,count) {
    io_layout_triple_indices(first,count);
    io_layout_index(first+1,count);
    io_layout_index(first+2,count);
    assert (first+2)*16==(first+1)*16+16;
}


requires size>=48 && size<=268435456;
requires at>=0 && at<=size-48 && (at&15)==0;
requires push_pc>=0 && push_pc<=268435440 && (push_pc&15)==0;
requires return_pc>push_pc && return_pc<=268435440 && (return_pc&15)==0;
requires readable_bytes(io_code+push_pc,16) && readable_bytes(io_code+return_pc,16);
requires load64(io_code+push_pc)==2 && load64(io_code+return_pc)==9;
requires disjoint_bytes(io_map,layout_map_size,io_code+push_pc,32);
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
requires readable_bytes(size_word,8);
requires disjoint_bytes(output,size,size_word,8);
requires load64(size_word)==compacted_size;
requires compacted_size>=48 && compacted_size<=size && (compacted_size&15)==0;
modifies bytes(output,size);
ensures result==0;
ensures load64(output+at+16)==2;
ensures load64(output+at+24)==expected_push;
ensures load64(output+at+32)==9;
ensures load64(output+at+40)==expected_return;
ensures load64(size_word)==compacted_size;
ensures load64(size_word)>=48;
ensures load64(size_word)<=size;
ensures (load64(size_word)&15)==0;
fn io_copy_in_output_buffer(push_pc,return_pc,at,size,expected_push,expected_return,layout_map_size,size_word,compacted_size) {
    proof {io_selected_copy_offsets(at,size);}
    io_copy_selected_push_and_return(push_pc,return_pc,at,size,expected_push,expected_return);
    proof {
        assert disjoint_bytes(output+at+16,16,size_word,8);
        assert disjoint_bytes(output+at+32,16,size_word,8);
        assert load64(size_word)==compacted_size;
        io_layout_copy_size_limit(load64(size_word),compacted_size,size);
    }
    return 0;
}


requires index>=0 && index<16777215;
ensures (index*16+16)/2==(index+1)*8;
lemma fn io_layout_next_pc_slot(index) {
    assert index*16+16==(index+1)*16;
    io_layout_pc_slot(index+1);
}

requires index>=0 && index<16777215;
requires readable_bytes(map+(index+1)*8,8);
ensures readable_bytes(map+(index*16+16)/2,8);
ensures load64(map+(index*16+16)/2)==load64(map+(index+1)*8);
lemma fn io_layout_adjacent_accessor_word(map,index) {
    io_layout_next_pc_slot(index);
    let actual=(index*16+16)/2;
    let expected=(index+1)*8;
    assert actual==expected;
    io_layout_same_map_delta(map,expected,actual);
}

requires expected==actual;
requires readable_bytes(map+expected,8);
ensures readable_bytes(map+actual,8);
ensures load64(map+actual)==load64(map+expected);
lemma fn io_layout_same_map_delta(map,expected,actual) {}

requires count>=3 && count<=16777216;
requires first>=0 && first<=count-3;
requires disjoint_bytes(output,count*16,io_map,(count+1)*8);
ensures disjoint_bytes(output,count*16,io_map+first*8,8);
lemma fn io_layout_header_map_separate(first,count) {
    io_layout_index(first,count);
    assert first*8>=0 && first*8<=(count+1)*8-8;
}

requires observed==compacted_size;
requires compacted_size<=capacity;
ensures observed<=capacity;
lemma fn io_layout_copy_size_limit(observed,compacted_size,capacity) {}
