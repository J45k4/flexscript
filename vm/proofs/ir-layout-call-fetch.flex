// Selected live CALL copy to the published bytecode and interpreter fetch.

requires mapped==at;
requires writable_bytes(base+at,16);
ensures writable_bytes(base+mapped,16);
lemma fn compacted_call_target_grant(base,mapped,at) {}

requires pc>=0 && pc<=268435440 && (pc&15)==0;
requires readable_bytes(io_flags+pc/16,1);
requires readable_bytes(io_map+pc/2,8);
requires load64(io_map+pc/2)==at;
requires readable_bytes(io_code+pc,16);
requires load64(io_code+pc)==8;
requires load64(io_code+pc+8)==index;
requires writable_bytes(output+at,16);
modifies bytes(output+at,16);
ensures result==0 || result==1;
ensures result==(old(load8(io_flags+pc/16))&1);
ensures result!=1 || load64(output+at)==8;
ensures result!=1 || load64(output+at+8)==index;
fn optimizer_copy_resolved_call(pc,at,index) {
    if io_live(pc) {
        proof {
            assert load64(io_map+pc/2)==at;
            compacted_call_target_grant(output,load64(io_map+pc/2),at);
            assert load64(io_code+pc)==8;
        }
        // Production resolved CALL copy.
        return 1;
    }
    return 0;
}


requires readable_bytes(entry,32);
requires readable_bytes(callee,16);
requires writable_bytes(destination,16);
requires disjoint_bytes(destination,16,entry,32);
requires disjoint_bytes(destination,16,callee,16);
ensures disjoint_bytes(destination,16,entry+16,8);
ensures disjoint_bytes(destination,16,entry+24,8);
ensures disjoint_bytes(destination,16,callee,8);
ensures disjoint_bytes(destination,16,callee+8,8);
lemma fn compacted_call_separates_callee(destination,entry,callee) {
    assert readable_bytes(entry+16,8);
    assert readable_bytes(entry+24,8);
    assert readable_bytes(callee+8,8);
}

requires pc>=0 && pc<=268435440 && (pc&15)==0;
requires size>=16 && size<=268435456;
requires at>=0 && at<=size-16 && (at&15)==0;
requires callee>=0 && callee<=size-16 && (callee&15)==0;
requires writable_bytes(output+at,16);
requires index>=0 && index<function_count;
requires function_count<=18432;
requires readable_bytes(functions+index*32,32);
requires load64(functions+index*32+16)==callee;
requires load64(functions+index*32+24)==arity;
requires readable_bytes(output+callee,16);
requires load64(output+callee)==18;
requires load64(output+callee+8)==slots;
requires disjoint_bytes(output+at,16,functions+index*32,32);
requires disjoint_bytes(output+at,16,output+callee,16);
requires readable_bytes(io_flags+pc/16,1);
requires (load8(io_flags+pc/16)&1)==1;
requires readable_bytes(io_map+pc/2,8);
requires load64(io_map+pc/2)==at;
requires readable_bytes(io_code+pc,16);
requires load64(io_code+pc)==8;
requires load64(io_code+pc+8)==index;
requires vm_depth>=0 && vm_depth<1024;
requires vm_pc==at && vm_fuel>=1;
requires vm_steps>=0 && vm_steps<0x7fffffffffffffff;
modifies output_size,vm_error,vm_pc,vm_fuel,vm_steps,bytes(output+at,16);
ensures result==1 && output_size==size;
ensures vm_pc==at+16 && vm_fuel==old(vm_fuel)-1 && vm_steps==old(vm_steps)+1;
ensures vm_error==old(vm_error);
ensures load64(output+at)==8;
ensures load64(output+at+8)==index;
fn optimizer_copy_call_to_ready_metadata(pc,at,size,index,callee,arity,slots) {
    let entry=functions+index*32;
    proof {
        compacted_call_separates_callee(output+at,entry,output+callee);
    }
    let copied=optimizer_copy_resolved_call(pc,at,index);
    // Production size publication.
    proof {
        assert copied==1;
        assert disjoint_bytes(output+at,16,entry+16,8);
        assert disjoint_bytes(output+at,16,entry+24,8);
        assert disjoint_bytes(output+at,16,output+callee,8);
        assert disjoint_bytes(output+at,16,output+callee+8,8);
        assert load64(output+at)==8;
        assert load64(output+at+8)==index;
        assert load64(entry+16)==callee;
        assert load64(entry+24)==arity;
        assert load64(output+callee)==18;
        assert load64(output+callee+8)==slots;
        assert vm_pc==at;
    }
    return vm_fetch_linked_call_metadata(at,index,callee,arity,slots);
}

requires writable_bytes(entry,32);
ensures disjoint_bytes(entry+16,8,entry+24,8);
lemma fn compacted_call_record_arity_separate(entry) {
    assert writable_bytes(entry+16,8);
    assert readable_bytes(entry+24,8);
}

requires call_pc>=0 && call_pc<=268435440 && (call_pc&15)==0;
requires callee_pc>=0 && callee_pc<call_pc && (callee_pc&15)==0;
requires size>=32 && size<=268435456;
requires at>=0 && at<=size-16 && (at&15)==0;
requires callee_at>=0 && callee_at<=size-16 && (callee_at&15)==0;
requires callee_at<at;
requires callee_pc<=268435440;
requires function_count>=1 && function_count<=18432;
requires index>=0 && index<function_count;
requires vm_depth>=0 && vm_depth<1024;
requires vm_pc==at && vm_fuel>=1;
requires vm_steps>=0 && vm_steps<0x7fffffffffffffff;
requires writable_bytes(output,size);
requires writable_bytes(output+at,16);
requires writable_bytes(output+callee_at,16);
requires writable_bytes(functions+index*32,32);
requires writable_bytes(functions+index*32+16,8);
requires load64(functions+index*32+16)==callee_pc;
requires load64(functions+index*32+24)==arity;
requires readable_bytes(io_code+call_pc,16);
requires load64(io_code+call_pc)==8;
requires load64(io_code+call_pc+8)==index;
requires readable_bytes(io_code+callee_pc,16);
requires load64(io_code+callee_pc)==18;
requires load64(io_code+callee_pc+8)==slots;
requires readable_bytes(io_map+call_pc/2,8);
requires load64(io_map+call_pc/2)==at;
requires readable_bytes(io_map+callee_pc/2,8);
requires load64(io_map+callee_pc/2)==callee_at;
requires readable_bytes(io_flags+call_pc/16,1);
requires (load8(io_flags+call_pc/16)&1)==1;
requires readable_bytes(io_flags+callee_pc/16,1);
requires (load8(io_flags+callee_pc/16)&1)==1;
requires disjoint_bytes(output,size,io_code+call_pc,16);
requires disjoint_bytes(output,size,io_map+call_pc/2,8);
requires disjoint_bytes(output,size,io_map+callee_pc/2,8);
requires disjoint_bytes(output,size,io_flags+call_pc/16,1);
requires disjoint_bytes(output,size,functions+index*32,32);
modifies output_size,vm_error,vm_pc,vm_fuel,vm_steps,bytes(output+at,16),
    bytes(output+callee_at,16),bytes(functions+index*32+16,8);
ensures result==1;
ensures output_size==size;
ensures vm_pc==at+16 && vm_fuel==old(vm_fuel)-1 && vm_steps==old(vm_steps)+1;
ensures vm_error==old(vm_error);
fn optimizer_compacted_call_to_vm_metadata(call_pc,callee_pc,at,callee_at,size,index,arity,slots) {
    let entry=functions+index*32;
    proof {
        assert callee_at<=size-16;
        assert callee_pc<=268435440;
        io_copy_separate_destinations(output,size,at,callee_at);
        io_copy_destination_grant(output,size,callee_at);
        io_copy_record_separate(entry,size,at);
        io_copy_record_separate(entry,size,callee_at);
        io_copy_map_word_separate(size,at,io_map+callee_pc/2);
        io_copy_map_word_separate(size,callee_at,io_map+call_pc/2);
        assert disjoint_bytes(output+callee_at,16,io_code+call_pc,16);
        assert disjoint_bytes(output+callee_at,16,io_flags+call_pc/16,1);
    }
    if io_live(callee_pc) {
        optimizer_writes_observed_header(callee_pc,callee_at,entry,slots,arity,size);
    }else {return 0;}
    proof {
        assert disjoint_bytes(output+callee_at,16,io_code+call_pc,16);
        assert disjoint_bytes(output+callee_at,16,io_map+call_pc/2,8);
        assert disjoint_bytes(output+callee_at,16,io_flags+call_pc/16,1);
        assert load64(io_code+call_pc)==8;
        assert load64(io_code+call_pc+8)==index;
        assert load64(io_map+call_pc/2)==at;
        assert (load8(io_flags+call_pc/16)&1)==1;
    }
    ghost let saved_callee_target=load64(io_map+callee_pc/2);
    proof {
        assert saved_callee_target==callee_at;
        assert disjoint_bytes(output+at,16,io_map+callee_pc/2,8);
    }
    let copied=optimizer_copy_resolved_call(call_pc,at,index);
    proof {assert copied==1;}

    proof {
        assert disjoint_bytes(output+at,16,io_map+callee_pc/2,8);
        assert disjoint_bytes(output+at,16,entry+16,8);
        assert disjoint_bytes(output+at,16,entry+24,8);
        assert load64(io_map+callee_pc/2)==saved_callee_target;
        io_copy_kept_value(load64(io_map+callee_pc/2),saved_callee_target,callee_at);
        assert load64(entry+16)==callee_pc;
        assert load64(entry+24)==arity;
    }
    ghost let before_arity=load64(entry+24);
    proof {compacted_call_record_arity_separate(entry);}
    io_relocate_function(entry,callee_pc);
    // Production size publication.
    proof {
        assert disjoint_bytes(output+at,16,entry+16,8);
        assert disjoint_bytes(output+callee_at,16,entry+16,8);
        assert disjoint_bytes(output+at,16,output+callee_at,16);
        assert load64(entry+16)==callee_at;
        assert disjoint_bytes(entry+16,8,entry+24,8);
        assert load64(entry+24)==before_arity;
        io_copy_kept_value(load64(entry+24),before_arity,arity);
        assert load64(output+callee_at)==18;
        assert load64(output+callee_at+8)==slots;
        assert load64(output+at)==8;
        assert load64(output+at+8)==index;
    }
    return vm_fetch_linked_call_metadata(at,index,callee_at,arity,slots);
}

requires pc>=0 && pc<=268435440 && (pc&15)==0;
requires readable_bytes(io_code+pc,16);
requires load64(io_code+pc)==18;
requires load64(io_code+pc+8)==slots;
requires writable_bytes(output+destination,16);
requires readable_bytes(output+call,16);
requires readable_bytes(entry,32);
requires readable_bytes(io_map+pc/2,8);
requires disjoint_bytes(output+destination,16,output+call,16);
requires disjoint_bytes(output+destination,16,entry+16,8);
requires disjoint_bytes(output+destination,16,entry+24,8);
requires disjoint_bytes(output+destination,16,io_map+pc/2,8);
modifies bytes(output+destination,16);
ensures result==0;
ensures load64(output+destination)==18;
ensures load64(output+destination+8)==slots;
ensures load64(output+call)==old(load64(output+call));
ensures load64(output+call+8)==old(load64(output+call+8));
ensures load64(entry+16)==old(load64(entry+16));
ensures load64(entry+24)==old(load64(entry+24));
ensures load64(io_map+pc/2)==old(load64(io_map+pc/2));
fn optimizer_copy_callee_preserving_call(pc,destination,call,entry,slots) {
    ghost let op=load64(output+call);
    ghost let operand=load64(output+call+8);
    ghost let saved_pc=load64(entry+16);
    ghost let arity=load64(entry+24);
    ghost let map=load64(io_map+pc/2);
    let copied=io_write_compacted_instruction(pc,destination);
    proof {
        assert disjoint_bytes(output+destination,16,output+call,16);
        assert disjoint_bytes(output+destination,16,entry+16,8);
        assert disjoint_bytes(output+destination,16,entry+24,8);
        assert disjoint_bytes(output+destination,16,io_map+pc/2,8);
        assert load64(output+call)==op;
        assert load64(output+call+8)==operand;
        assert load64(entry+16)==saved_pc;
        assert load64(entry+24)==arity;
        assert load64(io_map+pc/2)==map;
    }
    return copied;
}

requires call_pc>=0 && call_pc<=268435440 && (call_pc&15)==0;
requires callee_pc>=0 && call_pc<callee_pc && (callee_pc&15)==0;
requires size>=32 && size<=268435456;
requires at>=0 && at<=size-16 && (at&15)==0;
requires callee_at>=0 && callee_at<=size-16 && (callee_at&15)==0;
requires at<callee_at;
requires callee_pc<=268435440;
requires function_count>=1 && function_count<=18432;
requires index>=0 && index<function_count;
requires vm_depth>=0 && vm_depth<1024;
requires vm_pc==at && vm_fuel>=1;
requires vm_steps>=0 && vm_steps<0x7fffffffffffffff;
requires writable_bytes(output,size);
requires writable_bytes(output+at,16);
requires writable_bytes(output+callee_at,16);
requires writable_bytes(functions+index*32,32);
requires writable_bytes(functions+index*32+16,8);
requires load64(functions+index*32+16)==callee_pc;
requires load64(functions+index*32+24)==arity;
requires readable_bytes(io_code+call_pc,16);
requires load64(io_code+call_pc)==8;
requires load64(io_code+call_pc+8)==index;
requires readable_bytes(io_code+callee_pc,16);
requires load64(io_code+callee_pc)==18;
requires load64(io_code+callee_pc+8)==slots;
requires readable_bytes(io_map+call_pc/2,8);
requires load64(io_map+call_pc/2)==at;
requires readable_bytes(io_map+callee_pc/2,8);
requires load64(io_map+callee_pc/2)==callee_at;
requires readable_bytes(io_flags+call_pc/16,1);
requires (load8(io_flags+call_pc/16)&1)==1;
requires readable_bytes(io_flags+callee_pc/16,1);
requires (load8(io_flags+callee_pc/16)&1)==1;
requires disjoint_bytes(output,size,io_code+callee_pc,16);
requires disjoint_bytes(output,size,io_map+call_pc/2,8);
requires disjoint_bytes(output,size,io_map+callee_pc/2,8);
requires disjoint_bytes(output,size,io_flags+callee_pc/16,1);
requires disjoint_bytes(output,size,functions+index*32,32);
modifies output_size,vm_error,vm_pc,vm_fuel,vm_steps,bytes(output+at,16),
    bytes(output+callee_at,16),bytes(functions+index*32+16,8);
ensures result==1;
ensures output_size==size;
ensures vm_pc==at+16 && vm_fuel==old(vm_fuel)-1 && vm_steps==old(vm_steps)+1;
ensures vm_error==old(vm_error);
fn optimizer_compacted_call_before_callee(call_pc,callee_pc,at,callee_at,size,index,arity,slots) {
    let entry=functions+index*32;
    proof {
        io_copy_separate_destinations(output,size,at,callee_at);
        io_copy_record_separate(entry,size,at);
        io_copy_record_separate(entry,size,callee_at);
        io_copy_map_word_separate(size,at,io_map+callee_pc/2);
        io_copy_map_word_separate(size,callee_at,io_map+callee_pc/2);
        assert disjoint_bytes(output+at,16,io_code+callee_pc,16);
        assert disjoint_bytes(output+at,16,io_flags+callee_pc/16,1);
    }
    let copied=optimizer_copy_resolved_call(call_pc,at,index);
    proof {
        assert copied==1;
        assert disjoint_bytes(output+at,16,io_map+callee_pc/2,8);
        assert disjoint_bytes(output+at,16,io_code+callee_pc,16);
        assert disjoint_bytes(output+at,16,io_flags+callee_pc/16,1);
        assert disjoint_bytes(output+at,16,entry+16,8);
        assert disjoint_bytes(output+at,16,entry+24,8);
        assert load64(io_code+callee_pc)==18;
        assert load64(io_code+callee_pc+8)==slots;
        assert (load8(io_flags+callee_pc/16)&1)==1;
        assert load64(io_map+callee_pc/2)==callee_at;
        assert load64(entry+16)==callee_pc;
        assert load64(entry+24)==arity;
        assert load64(output+at)==8;
        assert load64(output+at+8)==index;
    }
    ghost let saved_pc=load64(entry+16);
    ghost let saved_arity=load64(entry+24);
    let callee_live=io_live(callee_pc);
    proof {assert callee_live==1;}
    if !callee_live {return 0;}
    let destination=io_compacted_offset(callee_pc);
    proof {
        assert destination==callee_at;
        assert writable_bytes(output+destination,16);
        assert load64(io_code+callee_pc)==18;
        assert disjoint_bytes(output+callee_at,16,entry+16,8);
        assert disjoint_bytes(output+callee_at,16,entry+24,8);
    }
    proof {
        assert disjoint_bytes(output+callee_at,16,output+at,16);
        assert disjoint_bytes(output+callee_at,16,io_map+callee_pc/2,8);
        assert load64(io_code+callee_pc+8)==slots;
    }
    optimizer_copy_callee_preserving_call(callee_pc,destination,at,entry,slots);
    proof {
        assert disjoint_bytes(output+callee_at,16,entry+16,8);
        assert disjoint_bytes(output+callee_at,16,entry+24,8);
        assert disjoint_bytes(output+callee_at,16,io_map+callee_pc/2,8);
        assert load64(entry+16)==saved_pc;
        assert load64(entry+24)==saved_arity;
        io_copy_kept_value(load64(entry+16),saved_pc,callee_pc);
        io_copy_kept_value(load64(entry+24),saved_arity,arity);
        assert load64(io_map+callee_pc/2)==callee_at;
        assert disjoint_bytes(output+at,16,output+callee_at,16);
        assert load64(output+at)==8;
        assert load64(output+at+8)==index;
        compacted_call_record_arity_separate(entry);
    }
    ghost let before_arity=load64(entry+24);
    io_relocate_function(entry,callee_pc);
    // Production size publication.
    proof {
        assert disjoint_bytes(entry+16,8,entry+24,8);
        assert disjoint_bytes(output+at,16,entry+16,8);
        assert disjoint_bytes(output+callee_at,16,entry+16,8);
        assert load64(entry+16)==callee_at;
        assert load64(entry+24)==before_arity;
        io_copy_kept_value(load64(entry+24),before_arity,arity);
        assert load64(output+callee_at)==18;
        assert load64(output+callee_at+8)==slots;
        assert load64(output+at)==8;
        assert load64(output+at+8)==index;
    }
    return vm_fetch_linked_call_metadata(at,index,callee_at,arity,slots);
}
