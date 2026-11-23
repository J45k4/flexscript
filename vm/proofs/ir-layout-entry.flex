import "ir-layout-copy.flex";

requires index>=0 && index<function_count;
requires vm_depth>=0 && vm_depth<1024;
requires output_size>=16 && output_size<=268435456;
requires expected_pc>=0 && expected_pc<=output_size-16 && (expected_pc&15)==0;
requires readable_bytes(functions+index*32,32);
requires load64(functions+index*32+16)==expected_pc;
requires load64(functions+index*32+24)==expected_count;
requires readable_bytes(output+expected_pc,16);
requires load64(output+expected_pc)==18;
requires load64(output+expected_pc+8)==expected_slots;
modifies nothing;
ensures result==1;
fn vm_enter_reads_copied_header(index,return_pc,expected_pc,expected_count,expected_slots) {
    // Production metadata reads.
    proof {
        assert pc==expected_pc;
        assert count==expected_count;
        assert slots==expected_slots;
    }
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
requires vm_depth>=0 && vm_depth<1024;
requires writable_bytes(functions+index*32,32);
requires load64(functions+index*32+16)==pc && load64(functions+index*32+24)==arity;
requires disjoint_bytes(output,compacted_size,io_map+pc/2,8);
requires disjoint_bytes(output,compacted_size,functions+index*32,32);
modifies bytes(output+at,16),bytes(functions+index*32+16,8),output_size;
ensures result==1;
fn optimizer_copies_header_to_vm_metadata(pc,at,slots,arity,compacted_size,index) {
    let entry=functions+index*32;
    optimizer_copies_and_rebinds_header(pc,at,entry,slots,arity,compacted_size);
    // Production size publication.
    proof {
        assert load64(functions+index*32+16)==at;
        assert load64(functions+index*32+24)==arity;
        assert load64(output+at)==18;
        assert load64(output+at+8)==slots;
    }
    return vm_enter_reads_copied_header(index,0,at,arity,slots);
}
