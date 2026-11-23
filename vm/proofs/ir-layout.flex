import "../../compiler/ir-layout.flex";
import "../call-frame.flex";

// The selected live header has been copied by the instruction pass. The
// function-record pass uses the same map entry, preserving arity and the
// header words while installing the PC consumed by the VM bounds guard.
requires pc>=0 && pc<=268435440 && (pc&15)==0;
requires compacted_size>=16 && compacted_size<=268435456;
requires at>=0 && at<=compacted_size-16 && (at&15)==0;
requires readable_bytes(io_map+pc/2,8);
requires load64(io_map+pc/2)==at;
requires readable_bytes(output+at,16);
requires load64(output+at)==18 && load64(output+at+8)==slots;
requires writable_bytes(entry,32);
requires load64(entry+16)==pc && load64(entry+24)==arity;
requires disjoint_bytes(output+at,16,entry+16,8);
modifies bytes(entry+16,8);
ensures load64(output+at)==18 && load64(output+at+8)==slots;
ensures load64(entry+16)==at && load64(entry+24)==arity;
ensures result==0;
fn optimizer_rebinds_compacted_header(pc,at,entry,slots,arity,compacted_size) {
    io_relocate_function(entry,pc);
    return vm_instruction_outside(load64(entry+16),compacted_size);
}
