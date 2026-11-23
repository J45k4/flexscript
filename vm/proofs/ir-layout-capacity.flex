// Capacity contract attached to the production body by the VM proof gate.
requires vm_depth>=0 && vm_depth<1024;
requires vm_sp>=0 && vm_sp<=524288;
requires vm_local_top>=0 && vm_local_top<=8388608;
requires vm_depth==0 || readable_bytes(vm_frames+(vm_depth-1)*40+24,8);
modifies vm_error;
ensures result==CAPACITY_DECISION;
ensures result==0 || vm_error==old(vm_error);
ensures result!=0 || vm_error==9;

// Call entry after header relocation.
requires index>=0 && index<function_count;
    // Call depth requirement.
requires output_size>=16 && output_size<=268435456;
requires expected_pc>=0 && expected_pc<=output_size-16 && (expected_pc&15)==0;
requires readable_bytes(functions+index*32,32);
requires load64(functions+index*32+16)==expected_pc;
requires load64(functions+index*32+24)==expected_count;
requires readable_bytes(output+expected_pc,16);
requires load64(output+expected_pc)==18;
requires load64(output+expected_pc+8)==expected_slots;
requires vm_sp>=0 && vm_sp<=524288;
requires vm_local_top>=0 && vm_local_top<=8388608;
requires expected_count>=0 && expected_count<=expected_slots && expected_slots<=4096;
requires expected_count*8<=vm_sp;
requires vm_local_top+expected_slots*8<=8388608;
    // Caller floor requirement.
modifies vm_error;
ensures result==1 && vm_error==old(vm_error);
fn vm_enter_accepts_copied_header_DEPTH_CASE(index,return_pc,expected_pc,expected_count,expected_slotsFLOOR_ARGUMENT) {
    // Production metadata reads.
    proof {
        assert pc==expected_pc;
        assert count==expected_count;
        assert slots==expected_slots;
    }
    // Production capacity decision.
    return 1;
}

// Selected copy and relocation followed by the final size assignment.
requires pc>=0 && pc<=268435440 && (pc&15)==0;
requires compacted_size>=16 && compacted_size<=268435456;
requires at>=0 && at<=compacted_size-16 && (at&15)==0;
requires readable_bytes(io_map+pc/2,8);
requires load64(io_map+pc/2)==at;
requires readable_bytes(io_code+pc,16);
requires load64(io_code+pc)==18 && load64(io_code+pc+8)==slots;
requires writable_bytes(output,compacted_size);
requires index>=0 && index<function_count;
    // Call depth requirement.
requires writable_bytes(functions+index*32,32);
requires load64(functions+index*32+16)==pc && load64(functions+index*32+24)==arity;
requires disjoint_bytes(output,compacted_size,io_map+pc/2,8);
requires disjoint_bytes(output,compacted_size,functions+index*32,32);
requires vm_sp>=0 && vm_sp<=524288;
requires vm_local_top>=0 && vm_local_top<=8388608;
requires arity>=0 && arity<=slots && slots<=4096;
requires arity*8<=vm_sp;
requires vm_local_top+slots*8<=8388608;
    // Active floor separation.
modifies bytes(output+at,16),bytes(functions+index*32+16,8),output_size,vm_error;
ensures result==1 && vm_error==old(vm_error);
fn optimizer_copies_header_to_vm_capacity_DEPTH_CASE(pc,at,slots,arity,compacted_size,indexFLOOR_ARGUMENT) {
    let entry=functions+index*32;
    // Selected floor address.
    optimizer_copies_and_rebinds_header(pc,at,entry,slots,arity,compacted_size);
    // Preservation of the active floor.
    // Production size publication.
    proof {
        assert load64(functions+index*32+16)==at;
        assert load64(functions+index*32+24)==arity;
        assert load64(output+at)==18;
        assert load64(output+at+8)==slots;
    }
    return vm_enter_accepts_copied_header_DEPTH_CASE(index,0,at,arity,slotsFLOOR_ARGUMENT);
}

// Capacity after a disjoint write.
requires observed==floor;
requires floor>=0 && floor<=cursor;
requires count_bytes<=cursor-floor;
ensures observed>=0;
ensures observed<=cursor;
ensures count_bytes<=cursor-observed;
lemma fn vm_copy_floor_keeps_capacity(observed,floor,cursor,count_bytes) {
    assert observed>=0 && observed<=cursor;
    assert cursor-observed==cursor-floor;
}

requires observed==floor;
ensures (observed>=0 && observed<=cursor && count_bytes<=cursor-observed)==(floor>=0 && floor<=cursor && count_bytes<=cursor-floor);
lemma fn vm_copy_floor_same_decision(observed,floor,cursor,count_bytes) {}
