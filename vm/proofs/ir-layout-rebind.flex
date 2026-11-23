// Connect the selected body copies to the production function-record relocation.
SCAN_COPY_REQUIREMENTS
requires writable_bytes(entry,32);
requires load64(entry+16)==first*16 && load64(entry+24)==arity;
requires disjoint_bytes(io_map,(count+1)*8,entry,32);
requires disjoint_bytes(output,count*16,entry,32);
modifies bytes(io_map,(count+1)*8),bytes(output,count*16),bytes(entry+16,8);
ensures load64(output+result+16)==2;
ensures load64(output+result+24)==old(load64(io_code+(first+1)*16+8));
ensures load64(output+result+32)==9;
ensures load64(output+result+40)==old(load64(io_code+(first+1)*16+24));
ensures load64(entry+16)==result;
ensures load64(entry+24)==arity;
ensures result>=0 && (result&15)==0 && result<=load64(io_map+count*8)-48;
fn optimizer_scan_copy_rebind_entry(count,first,entry,arity) {
    let pc=first*16;
    proof {
        io_layout_triple_indices(first,count);
        io_layout_pc_slot(first);
        io_record_words_separate(io_map,(count+1)*8,entry);
        io_record_words_separate(output,count*16,entry);
    }
    ghost let original_push=load64(io_code+(first+1)*16+8);
    ghost let original_return=load64(io_code+(first+1)*16+24);
    ghost let prior_pc=load64(entry+16);
    ghost let prior_arity=load64(entry+24);
    proof {
        assert prior_pc==pc;
        assert prior_arity==arity;
    }
    let at=io_build_layout_then_copy_selected_body(count,first);
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
        assert disjoint_bytes(output+at+16,16,entry+16,8);
        assert disjoint_bytes(output+at+32,16,entry+16,8);
        assert disjoint_bytes(io_map+count*8,8,entry+16,8);
    }
    io_relocate_expected_record(entry,pc,at,arity);
    proof {
        assert disjoint_bytes(output+at+16,16,entry+16,8);
        assert disjoint_bytes(output+at+32,16,entry+16,8);
        assert load64(output+at+24)==original_push;
        assert load64(output+at+40)==original_return;
    }
    return at;
}

// Record relocation lemmas and wrapper.
requires length>=0 && length<=268435456;
requires disjoint_bytes(base,length,entry,32);
ensures disjoint_bytes(base,length,entry+16,8);
ensures disjoint_bytes(base,length,entry+24,8);
lemma fn io_record_words_separate(base,length,entry) {}

requires count>=3 && count<=16777216;
requires at>=0 && at<=count*16-48 && (at&15)==0;
requires disjoint_bytes(output,count*16,entry,32);
requires disjoint_bytes(io_map,(count+1)*8,entry,32);
ensures disjoint_bytes(output+at,16,entry+16,8);
ensures disjoint_bytes(output+at+16,16,entry+16,8);
ensures disjoint_bytes(output+at+32,16,entry+16,8);
ensures disjoint_bytes(io_map+count*8,8,entry+16,8);
lemma fn io_rebind_watched_spans(count,at,entry) {
    io_record_words_separate(output,count*16,entry);
    io_record_words_separate(io_map,(count+1)*8,entry);
    assert count*16>=48 && count*16<=268435456;
    io_selected_copy_offsets(at,count*16);
    assert count*8>=0 && count*8==(count+1)*8-8;
}

requires writable_bytes(entry,32);
requires load64(entry+16)==pc;
requires load64(entry+24)==arity;
requires readable_bytes(io_map+pc/2,8);
requires load64(io_map+pc/2)==at;
modifies bytes(entry+16,8);
ensures result==0;
ensures load64(entry+16)==at;
ensures load64(entry+24)==arity;
fn io_relocate_expected_record(entry,pc,at,arity) {
    let source_pc=load64(entry+16);
    proof {assert source_pc==pc;}
    return io_relocate_function(entry,source_pc);
}
