import "../frame-state.flex";

// An empty frame stack traps without needing any byte-memory permission.
requires vm_depth == 0;
reads vm_depth,vm_error;
modifies vm_error;
ensures result == 0 && vm_error == 9;
ensures vm_depth == 0;
fn frame_return_empty() {return vm_return();}

// Exact restoration permits arbitrary saved words. The separate bounds
// profile below requires and preserves the saved metadata's range invariants.
requires vm_depth >= 1 && vm_depth <= 1024;
requires readable_bytes(vm_frames+(vm_depth-1)*40,32);
reads vm_depth,vm_frames,vm_pc,vm_local_base,vm_local_top,vm_sp,vm_finished,vm_error,bytes(vm_frames+(vm_depth-1)*40,32);
modifies vm_depth,vm_pc,vm_local_base,vm_local_top,vm_sp,vm_finished;
ensures result == 0 && vm_error == old(vm_error);
ensures vm_depth == old(vm_depth)-1;
ensures vm_pc == old(load64(vm_frames+(vm_depth-1)*40));
ensures vm_local_base == old(load64(vm_frames+(vm_depth-1)*40+8));
ensures vm_local_top == old(load64(vm_frames+(vm_depth-1)*40+16));
ensures vm_sp == old(load64(vm_frames+(vm_depth-1)*40+24));
ensures vm_pc != -1 || vm_finished == 1;
ensures vm_pc == -1 || vm_finished == old(vm_finished);
fn frame_return_saved() {return vm_return();}

// These metadata premises must ultimately follow from checked call entry and
// initialization. This theorem does not assume ownership of stack/local bytes:
// return itself accesses only the saved fields, and never writes byte memory.
requires vm_depth >= 1 && vm_depth <= 1024;
requires vm_error == 0 && vm_finished == 0;
requires code_size >= 16 && (code_size & 15) == 0;
requires readable_bytes(vm_frames+(vm_depth-1)*40,32);
requires load64(vm_frames+(vm_depth-1)*40) == -1 || (load64(vm_frames+(vm_depth-1)*40) >= 0 && load64(vm_frames+(vm_depth-1)*40) <= code_size && (load64(vm_frames+(vm_depth-1)*40) & 15) == 0);
requires load64(vm_frames+(vm_depth-1)*40+8) >= 0 && load64(vm_frames+(vm_depth-1)*40+8) <= load64(vm_frames+(vm_depth-1)*40+16);
requires load64(vm_frames+(vm_depth-1)*40+16) <= 8388608;
requires load64(vm_frames+(vm_depth-1)*40+24) >= 0 && load64(vm_frames+(vm_depth-1)*40+24) <= 524288 && (load64(vm_frames+(vm_depth-1)*40+24) & 7) == 0;
reads vm_depth,vm_frames,vm_pc,vm_local_base,vm_local_top,vm_sp,vm_finished,vm_error,bytes(vm_frames+(vm_depth-1)*40,32);
modifies vm_depth,vm_pc,vm_local_base,vm_local_top,vm_sp,vm_finished;
ensures result == 0 && vm_error == 0;
ensures vm_depth == old(vm_depth)-1 && vm_depth >= 0 && vm_depth <= 1023;
ensures vm_local_base >= 0 && vm_local_base <= vm_local_top && vm_local_top <= 8388608;
ensures vm_sp >= 0 && vm_sp <= 524288 && (vm_sp & 7) == 0;
ensures vm_sp == old(load64(vm_frames+(vm_depth-1)*40+24));
ensures vm_pc == -1 || (vm_pc >= 0 && vm_pc <= code_size && (vm_pc & 15) == 0);
ensures vm_finished == (vm_pc == -1);
fn frame_return_bounds(code_size) {return frame_return_saved();}

// Initialization owns the complete 1,024-record frame buffer. Derive the
// exact four-field read grant used by return, including the final record.
requires depth >= 1 && depth <= 1024;
requires readable_bytes(frames,40960);
ensures readable_bytes(frames+(depth-1)*40,32);
lemma fn frame_top_permission(frames,depth) {
    proof {frame_stride_bounds(depth);frame_slot_permission(frames,(depth-1)*40);}
}

requires depth >= 1 && depth <= 1024;
ensures (depth-1)*40 >= 0 && (depth-1)*40 <= 40920;
lemma fn frame_stride_bounds(depth) {}

requires offset >= 0 && offset <= 40928;
requires readable_bytes(frames,40960);
ensures readable_bytes(frames+offset,32);
lemma fn frame_slot_permission(frames,offset) {}

// A checked specification reader can establish the slot grant before reading
// metadata in an enclosing contract's ordered requirements.
requires depth >= 1 && depth <= 1024;
requires readable_bytes(frames,40960);
reads bytes(frames,40960);
modifies nothing;
ensures result == load64(frames+(depth-1)*40+24);
spec fn frame_saved_floor(frames,depth) {
    proof {frame_top_permission(frames,depth);}
    return load64(frames+(depth-1)*40+24);
}

requires depth >= 2 && depth <= 1024;
requires readable_bytes(frames,40960);
reads bytes(frames,40960);
modifies nothing;
spec fn frame_floor_chain(frames,depth) {
    proof {frame_top_permission(frames,depth);frame_top_permission(frames,depth-1);}
    let top=load64(frames+(depth-1)*40+24);
    let parent=load64(frames+(depth-2)*40+24);
    return parent>=0 && parent<=top && top<=524288;
}

requires vm_depth >= 1 && vm_depth <= 1024;
requires readable_bytes(vm_frames,40960);
reads vm_depth,vm_frames,vm_pc,vm_local_base,vm_local_top,vm_sp,vm_finished,vm_error,bytes(vm_frames,40960);
modifies vm_depth,vm_pc,vm_local_base,vm_local_top,vm_sp,vm_finished;
ensures result == 0 && vm_error == old(vm_error);
ensures vm_depth == old(vm_depth)-1;
ensures vm_pc == old(load64(vm_frames+(vm_depth-1)*40));
ensures vm_local_base == old(load64(vm_frames+(vm_depth-1)*40+8));
ensures vm_local_top == old(load64(vm_frames+(vm_depth-1)*40+16));
ensures vm_sp == old(load64(vm_frames+(vm_depth-1)*40+24));
ensures vm_pc != -1 || vm_finished == 1;
ensures vm_pc == -1 || vm_finished == old(vm_finished);
fn frame_return_buffer() {
    proof {frame_top_permission(vm_frames,vm_depth);}
    return frame_return_saved();
}

// A monotone pair of saved floors must remain valid when the callee returns.
// The checked predicate/reader establish their read grants before accessing
// metadata; call entry still has to create and preserve this chain premise.
requires vm_depth >= 2 && vm_depth <= 1024;
requires readable_bytes(vm_frames,40960);
requires frame_floor_chain(vm_frames,vm_depth);
reads vm_depth,vm_frames,vm_pc,vm_local_base,vm_local_top,vm_sp,vm_finished,vm_error,bytes(vm_frames,40960);
modifies vm_depth,vm_pc,vm_local_base,vm_local_top,vm_sp,vm_finished;
ensures vm_depth == old(vm_depth)-1;
ensures vm_sp >= 0 && vm_sp <= 524288;
ensures vm_sp >= frame_saved_floor(vm_frames,vm_depth);
ensures result == 0 && vm_error == old(vm_error);
fn frame_return_floor() {return frame_return_buffer();}

// Compose the metadata bounds with the active caller-floor invariant for a
// returning nested call. The source executor checks the same production return
// through the bounds profile; its exact saved-cursor summary links the floors.
requires vm_depth >= 2 && vm_depth <= 1024;
requires readable_bytes(vm_frames,40960);
requires frame_floor_chain(vm_frames,vm_depth);
requires vm_error == 0 && vm_finished == 0;
requires code_size >= 16 && (code_size & 15) == 0;
requires load64(vm_frames+(vm_depth-1)*40) == -1 || (load64(vm_frames+(vm_depth-1)*40) >= 0 && load64(vm_frames+(vm_depth-1)*40) <= code_size && (load64(vm_frames+(vm_depth-1)*40) & 15) == 0);
requires load64(vm_frames+(vm_depth-1)*40+8) >= 0 && load64(vm_frames+(vm_depth-1)*40+8) <= load64(vm_frames+(vm_depth-1)*40+16);
requires load64(vm_frames+(vm_depth-1)*40+16) <= 8388608;
requires (load64(vm_frames+(vm_depth-1)*40+24) & 7) == 0;
reads vm_depth,vm_frames,vm_pc,vm_local_base,vm_local_top,vm_sp,vm_finished,vm_error,bytes(vm_frames,40960);
modifies vm_depth,vm_pc,vm_local_base,vm_local_top,vm_sp,vm_finished;
ensures result == 0 && vm_error == 0;
ensures vm_depth == old(vm_depth)-1 && vm_depth >= 1 && vm_depth <= 1023;
ensures vm_local_base >= 0 && vm_local_base <= vm_local_top && vm_local_top <= 8388608;
ensures vm_sp >= 0 && vm_sp <= 524288 && (vm_sp & 7) == 0;
ensures vm_sp >= frame_saved_floor(vm_frames,vm_depth);
ensures vm_pc == -1 || (vm_pc >= 0 && vm_pc <= code_size && (vm_pc & 15) == 0);
ensures vm_finished == (vm_pc == -1);
fn frame_return_state(code_size) {return frame_return_bounds(code_size);}
