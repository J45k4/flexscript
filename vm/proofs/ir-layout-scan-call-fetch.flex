// Compose the ordered production layout scan with the selected CALL paths.

requires count>=2 && count<=16777216;
requires callee>=0 && callee<call && call<count;
requires index>=0 && index<function_count && function_count<=18432;
requires vm_depth>=0 && vm_depth<1024;
requires vm_fuel>=1;
requires vm_steps>=0 && vm_steps<0x7fffffffffffffff;
requires writable_bytes(io_map,(count+1)*8);
requires readable_bytes(io_flags,count);
requires readable_bytes(io_map+call*8,8);
requires readable_bytes(io_map+callee*8,8);
requires readable_bytes(io_flags+call,1);
requires readable_bytes(io_flags+callee,1);
requires (load8(io_flags+call)&1)==1;
requires (load8(io_flags+callee)&1)==1;
requires disjoint_bytes(io_map,(count+1)*8,io_flags,count);
requires writable_bytes(output,count*16);
requires writable_bytes(functions+index*32,32);
requires writable_bytes(functions+index*32+16,8);
requires load64(functions+index*32+16)==callee*16;
requires load64(functions+index*32+24)==arity;
requires readable_bytes(io_code+call*16,16);
requires load64(io_code+call*16)==8;
requires load64(io_code+call*16+8)==index;
requires readable_bytes(io_code+callee*16,16);
requires load64(io_code+callee*16)==18;
requires load64(io_code+callee*16+8)==slots;
requires disjoint_bytes(io_map,(count+1)*8,functions+index*32,32);
requires disjoint_bytes(io_map,(count+1)*8,io_code+call*16,16);
requires disjoint_bytes(io_map,(count+1)*8,io_code+callee*16,16);
requires disjoint_bytes(output,count*16,io_map,(count+1)*8);
requires disjoint_bytes(output,count*16,io_code+call*16,16);
requires disjoint_bytes(output,count*16,io_flags+call,1);
requires disjoint_bytes(output,count*16,functions+index*32,32);
modifies output_size,vm_error,vm_pc,vm_fuel,vm_steps,bytes(io_map,(count+1)*8),
    bytes(output,count*16),bytes(functions+index*32+16,8);
ensures result==1;
ensures output_size>=32 && output_size<=count*16;
ensures vm_fuel==old(vm_fuel)-1 && vm_steps==old(vm_steps)+1;
ensures vm_error==old(vm_error);
fn scan_relocate_and_fetch_selected_call(count,callee,call,index,arity,slots) {
    let entry=functions+index*32;
    let call_pc=call*16;
    let callee_pc=callee*16;
    proof {
        compacted_call_source_offsets(call);
        compacted_call_source_offsets(callee);
        assert callee_pc<call_pc;
        io_record_words_separate(io_map,(count+1)*8,entry);
        compacted_call_scan_bounds(count,callee,call);
        assert readable_bytes(io_map+callee*8,8);
        assert readable_bytes(io_map+call*8,8);
        assert readable_bytes(io_flags+callee,1);
        assert readable_bytes(io_flags+call,1);
        assert (load8(io_flags+callee)&1)==1;
        assert (load8(io_flags+call)&1)==1;
    }
    let size=io_build_layout_ordered_live_pair(count,callee,call);
    proof {
        assert size>=32;
        assert size<=count*16;
    }
    let at=optimizer_read_mapped_slot(call,call_pc);
    let callee_at=optimizer_read_mapped_slot(callee,callee_pc);
    proof {
        assert at==load64(io_map+call*8);
        assert callee_at==load64(io_map+callee*8);
        assert callee_at<at;
        assert at>=0 && at<=size-16 && (at&15)==0;
        assert callee_at>=0 && callee_at<=size-16 && (callee_at&15)==0;
        io_record_words_separate(io_map,(count+1)*8,entry);
        assert disjoint_bytes(io_map,(count+1)*8,io_code+call_pc,16);
        assert disjoint_bytes(io_map,(count+1)*8,io_code+callee_pc,16);
        assert load64(entry+16)==callee_pc;
        assert load64(entry+24)==arity;
        assert load64(io_code+call_pc)==8;
        assert load64(io_code+call_pc+8)==index;
        assert load64(io_code+callee_pc)==18;
        assert load64(io_code+callee_pc+8)==slots;
        assert count*16>=32 && count*16<=268435456;
        assert disjoint_bytes(output,count*16,io_map,(count+1)*8);
        compacted_call_output_prefix(output,count*16,size,io_map,(count+1)*8);
        compacted_call_output_prefix(output,count*16,size,io_code+call_pc,16);
        compacted_call_output_prefix(output,count*16,size,io_flags+call,1);
        compacted_call_output_prefix(output,count*16,size,entry,32);
        compacted_call_map_word_separate(output,size,io_map,count,call);
        compacted_call_map_word_separate(output,size,io_map,count,callee);
        compacted_call_destinations_fit(at,callee_at,size,count*16);
        io_copy_destination_grant(output,size,at);
        io_copy_destination_grant(output,size,callee_at);
        assert io_map+call_pc/2==io_map+call*8;
        assert io_map+callee_pc/2==io_map+callee*8;
        assert io_flags+call_pc/16==io_flags+call;
        assert io_flags+callee_pc/16==io_flags+callee;
        io_layout_same_word(io_map+call*8,io_map+call_pc/2);
        io_layout_same_word(io_map+callee*8,io_map+callee_pc/2);
        io_layout_same_flag(io_flags+call,io_flags+call_pc/16);
        io_layout_same_flag(io_flags+callee,io_flags+callee_pc/16);
        assert load64(io_map+call_pc/2)==at;
        assert load64(io_map+callee_pc/2)==callee_at;
        assert (load8(io_flags+call_pc/16)&1)==1;
        assert (load8(io_flags+callee_pc/16)&1)==1;
        assert disjoint_bytes(output,size,io_map+call_pc/2,8);
        assert disjoint_bytes(output,size,io_map+callee_pc/2,8);
        assert disjoint_bytes(output,size,io_flags+call_pc/16,1);
    }
    // Select the relocated instruction as the starting PC for the one step.
    vm_pc=at;
    return optimizer_compacted_call_to_vm_metadata(call_pc,callee_pc,at,callee_at,size,index,arity,slots);
}

requires count>=2 && count<=16777216;
requires call>=0 && call<callee && callee<count;
requires index>=0 && index<function_count && function_count<=18432;
requires vm_depth>=0 && vm_depth<1024;
requires vm_fuel>=1;
requires vm_steps>=0 && vm_steps<0x7fffffffffffffff;
requires writable_bytes(io_map,(count+1)*8);
requires readable_bytes(io_flags,count);
requires readable_bytes(io_map+call*8,8);
requires readable_bytes(io_map+callee*8,8);
requires readable_bytes(io_flags+call,1);
requires readable_bytes(io_flags+callee,1);
requires (load8(io_flags+call)&1)==1;
requires (load8(io_flags+callee)&1)==1;
requires disjoint_bytes(io_map,(count+1)*8,io_flags,count);
requires writable_bytes(output,count*16);
requires writable_bytes(functions+index*32,32);
requires writable_bytes(functions+index*32+16,8);
requires load64(functions+index*32+16)==callee*16;
requires load64(functions+index*32+24)==arity;
requires readable_bytes(io_code+call*16,16);
requires load64(io_code+call*16)==8;
requires load64(io_code+call*16+8)==index;
requires readable_bytes(io_code+callee*16,16);
requires load64(io_code+callee*16)==18;
requires load64(io_code+callee*16+8)==slots;
requires disjoint_bytes(io_map,(count+1)*8,functions+index*32,32);
requires disjoint_bytes(io_map,(count+1)*8,io_code+call*16,16);
requires disjoint_bytes(io_map,(count+1)*8,io_code+callee*16,16);
requires disjoint_bytes(output,count*16,io_map,(count+1)*8);
requires disjoint_bytes(output,count*16,io_code+callee*16,16);
requires disjoint_bytes(output,count*16,io_flags+callee,1);
requires disjoint_bytes(output,count*16,functions+index*32,32);
modifies output_size,vm_error,vm_pc,vm_fuel,vm_steps,bytes(io_map,(count+1)*8),
    bytes(output,count*16),bytes(functions+index*32+16,8);
ensures result==1;
ensures output_size>=32 && output_size<=count*16;
ensures vm_fuel==old(vm_fuel)-1 && vm_steps==old(vm_steps)+1;
ensures vm_error==old(vm_error);
fn scan_relocate_and_fetch_call_before_callee(count,callee,call,index,arity,slots) {
    let entry=functions+index*32;
    let call_pc=call*16;
    let callee_pc=callee*16;
    proof {
        compacted_call_source_offsets(call);
        compacted_call_source_offsets(callee);
        assert call_pc<callee_pc;
        io_record_words_separate(io_map,(count+1)*8,entry);
        compacted_call_scan_bounds(count,call,callee);
        assert readable_bytes(io_map+callee*8,8);
        assert readable_bytes(io_map+call*8,8);
        assert readable_bytes(io_flags+callee,1);
        assert readable_bytes(io_flags+call,1);
        assert (load8(io_flags+callee)&1)==1;
        assert (load8(io_flags+call)&1)==1;
    }
    let size=io_build_layout_ordered_live_pair(count,call,callee);
    proof {
        assert size>=32;
        assert size<=count*16;
    }
    let at=optimizer_read_mapped_slot(call,call_pc);
    let callee_at=optimizer_read_mapped_slot(callee,callee_pc);
    proof {
        assert at==load64(io_map+call*8);
        assert callee_at==load64(io_map+callee*8);
        assert at<callee_at;
        assert at>=0 && at<=size-16 && (at&15)==0;
        assert callee_at>=0 && callee_at<=size-16 && (callee_at&15)==0;
        io_record_words_separate(io_map,(count+1)*8,entry);
        assert disjoint_bytes(io_map,(count+1)*8,io_code+call_pc,16);
        assert disjoint_bytes(io_map,(count+1)*8,io_code+callee_pc,16);
        assert load64(entry+16)==callee_pc;
        assert load64(entry+24)==arity;
        assert load64(io_code+call_pc)==8;
        assert load64(io_code+call_pc+8)==index;
        assert load64(io_code+callee_pc)==18;
        assert load64(io_code+callee_pc+8)==slots;
        assert count*16>=32 && count*16<=268435456;
        assert disjoint_bytes(output,count*16,io_map,(count+1)*8);
        compacted_call_output_prefix(output,count*16,size,io_map,(count+1)*8);
        compacted_call_output_prefix(output,count*16,size,io_code+callee_pc,16);
        compacted_call_output_prefix(output,count*16,size,io_flags+callee,1);
        compacted_call_output_prefix(output,count*16,size,entry,32);
        compacted_call_map_word_separate(output,size,io_map,count,call);
        compacted_call_map_word_separate(output,size,io_map,count,callee);
        compacted_call_destinations_fit(at,callee_at,size,count*16);
        io_copy_destination_grant(output,size,at);
        io_copy_destination_grant(output,size,callee_at);
        assert io_map+call_pc/2==io_map+call*8;
        assert io_map+callee_pc/2==io_map+callee*8;
        assert io_flags+call_pc/16==io_flags+call;
        assert io_flags+callee_pc/16==io_flags+callee;
        io_layout_same_word(io_map+call*8,io_map+call_pc/2);
        io_layout_same_word(io_map+callee*8,io_map+callee_pc/2);
        io_layout_same_flag(io_flags+call,io_flags+call_pc/16);
        io_layout_same_flag(io_flags+callee,io_flags+callee_pc/16);
        assert load64(io_map+call_pc/2)==at;
        assert load64(io_map+callee_pc/2)==callee_at;
        assert (load8(io_flags+call_pc/16)&1)==1;
        assert (load8(io_flags+callee_pc/16)&1)==1;
        assert disjoint_bytes(output,size,io_map+call_pc/2,8);
        assert disjoint_bytes(output,size,io_map+callee_pc/2,8);
        assert disjoint_bytes(output,size,io_flags+callee_pc/16,1);
    }
    // Select the relocated instruction as the starting PC for the one step.
    vm_pc=at;
    return optimizer_compacted_call_before_callee(call_pc,callee_pc,at,callee_at,size,index,arity,slots);
}


requires length>=0 && length<=268435456;
requires disjoint_bytes(base,length,entry,32);
ensures disjoint_bytes(base,length,entry+16,8);
ensures disjoint_bytes(base,length,entry+24,8);
lemma fn io_record_words_separate(base,length,entry) {}

requires count>=2 && count<=16777216;
requires index>=0 && index<count;
requires disjoint_bytes(code,size,map,(count+1)*8);
ensures disjoint_bytes(code,size,map+index*8,8);
lemma fn compacted_call_map_word_separate(code,size,map,count,index) {
    io_layout_index(index,count);
    assert index*8<=(count+1)*8-8;
}

requires index>=0 && index<16777216;
ensures index*16>=0 && index*16<=268435440 && ((index*16)&15)==0;
ensures (index*16)/2==index*8 && (index*16)/16==index;
lemma fn compacted_call_source_offsets(index) {}

requires capacity>=32 && capacity<=268435456;
requires size>=32;
requires size<=capacity;
requires writable_bytes(code,capacity);
requires disjoint_bytes(code,capacity,source,source_size);
ensures writable_bytes(code,size);
ensures disjoint_bytes(code,size,source,source_size);
lemma fn compacted_call_output_prefix(code,capacity,size,source,source_size) {}

requires index>=0 && index<16777216;
requires pc==index*16;
requires readable_bytes(io_map+index*8,8);
ensures result==load64(io_map+index*8);
fn optimizer_read_mapped_slot(index,pc) {
    proof {
        compacted_call_source_offsets(index);
        assert pc/2==index*8;
        assert io_map+pc/2==io_map+index*8;
    }
    let mapped=io_compacted_offset(pc);
    proof {
        assert mapped==load64(io_map+pc/2);
        assert mapped==load64(io_map+index*8);
    }
    return mapped;
}

requires count>=2 && count<=16777216;
requires callee>=0 && callee<call && call<count;
ensures callee>=0 && callee<count;
ensures call>=0 && call>callee && call<count;
ensures count*16>=32 && count*16<=268435456;
lemma fn compacted_call_scan_bounds(count,callee,call) {}



requires capacity>=32 && capacity<=268435456;
requires size>=32 && size<=capacity;
requires at>=0 && at<=size-16;
requires callee_at>=0 && callee_at<=size-16;
ensures at<=capacity-16;
ensures callee_at<=capacity-16;
lemma fn compacted_call_destinations_fit(at,callee_at,size,capacity) {}
