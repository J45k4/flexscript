import "../call-frame.flex";

// Call-entry rejection profiles. The remaining capacity rejection and
// acceptance paths are in proofs/pending/call-entry.flex.

// Out-of-range index or a full frame stack: the production guard rejects
// before touching any byte memory, and every other global is preserved.
requires index < 0 || index >= function_count || vm_depth >= 1024;
reads vm_depth,vm_error,function_count;
modifies vm_error;
ensures result == 0 && vm_error == 4;
ensures vm_depth == old(vm_depth);
fn enter_rejects_bad_index(index,return_pc) {return vm_enter(index,return_pc);}

// Reject invalid offsets with no read grant for the bytecode buffer.
requires index >= 0 && index < function_count;
requires vm_depth >= 0 && vm_depth <= 1023;
requires readable_bytes(functions+index*32+16,8);
requires output_size<16 || load64(functions+index*32+16)<0 || load64(functions+index*32+16)>output_size-16 || (load64(functions+index*32+16)&15)!=0;
reads vm_depth,vm_error,function_count,functions,output_size,bytes(functions+index*32+16,8);
modifies vm_error;
ensures result == 0 && vm_error == 9;
fn enter_rejects_bad_pc(index,return_pc) {return vm_enter(index,return_pc);}

// A malformed header needs only the function's PC field and the opcode word.
// The read frame excludes the arity, slots, operands and locals. The write
// frame permits only the error flag, so no frame state or memory can change.
requires index >= 0 && index < function_count;
requires vm_depth >= 0 && vm_depth <= 1023;
requires readable_bytes(functions+index*32+16,8);
requires !(output_size<16 || load64(functions+index*32+16)<0 || load64(functions+index*32+16)>output_size-16 || (load64(functions+index*32+16)&15)!=0);
requires readable_bytes(output+load64(functions+index*32+16),8);
requires load64(output+load64(functions+index*32+16)) != 18;
reads vm_depth,vm_error,vm_pc,function_count,functions,output,output_size,bytes(functions+index*32+16,8),bytes(output+load64(functions+index*32+16),8);
modifies vm_error;
ensures result == 0 && vm_error == 9;
ensures vm_depth == old(vm_depth) && vm_pc == old(vm_pc);
fn enter_rejects_opcode(index,return_pc) {return vm_enter(index,return_pc);}

// Shared instruction bounds. The largest current compiler output limit is
// 256 MiB. Accepted pairs have a nonwrapping, aligned offset and a complete
// 16-byte span. The offset predicate alone does not grant memory permission.
requires size >= 0 && size <= 268435456;
reads nothing;
modifies nothing;
ensures result == 0 || result == 1;
ensures result != 0 || (size>=16 && pc<=size-16);
ensures result != 0 || (pc>=0 && (pc&15)==0 && pc+16>pc && pc+16<=size);
ensures result == 0 || !(size>=16 && pc>=0 && (pc&15)==0 && pc<=size-16);
fn instruction_pair_bounds(pc,size) {return vm_instruction_outside(pc,size);}

requires pc >= 0 && pc <= 268435440 && (pc&15)==0;
reads nothing;
modifies nothing;
ensures result == 0;
fn instruction_pair_accepts_exact_fit(pc) {return vm_instruction_outside(pc,pc+16);}

// Reject every size below one instruction, including negative words whose
// subtraction would wrap. No upper bound or alignment premise on the PC.
requires size<16;
reads nothing;
modifies nothing;
ensures result == 1;
fn instruction_pair_rejects_short_size(pc,size) {return vm_instruction_outside(pc,size);}

// Derive the instruction read grant from ownership of the entire code span.
// The span length and position are both symbolic.
requires size>=16 && size<=268435456;
requires offset>=0 && offset<=size-16;
requires readable_bytes(code,size);
ensures readable_bytes(code+offset,16);
lemma fn instruction_pair_permission(code,size,offset) {}

requires size>=0 && size<=268435456;
requires readable_bytes(code,size);
reads bytes(code,size);
modifies nothing;
ensures result != 0 || readable_bytes(code+pc,16);
fn instruction_pair_buffer(code,pc,size) {
    let outside=instruction_pair_bounds(pc,size);
    if !outside {
        proof {instruction_pair_permission(code,size,pc);}
    }
    return outside;
}
