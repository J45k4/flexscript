import "../call-frame.flex";

// A call may consume only operands above the active caller's floor. These
// states have valid bounded metadata but insufficient arguments in that frame.
requires vm_depth >= 1 && vm_depth <= 1023;
requires vm_sp >= 0 && vm_sp <= 524288;
requires vm_local_top >= 0 && vm_local_top <= 8388608;
requires vm_error == 0;
requires count >= 0 && count <= slots && slots <= 4096;
requires readable_bytes(vm_frames,40960);
requires readable_bytes(vm_frames+(vm_depth-1)*40+24,8);
requires load64(vm_frames+(vm_depth-1)*40+24) >= 0 && load64(vm_frames+(vm_depth-1)*40+24) <= vm_sp;
requires count*8 > vm_sp-load64(vm_frames+(vm_depth-1)*40+24);
reads vm_depth,vm_frames,vm_sp,vm_local_top,vm_error,bytes(vm_frames+(vm_depth-1)*40+24,8);
modifies vm_error;
ensures result == 0 && vm_error == 9;
fn call_rejects_frame_underflow(count,slots) {
    proof {
        assert vm_depth != 0;
    }
    return vm_call_capacity(count,slots);
}

requires cursor >= 0 && cursor <= 524288;
requires floor >= 0 && floor <= cursor;
requires count >= 0 && count <= 4096;
requires count*8 > cursor-floor;
ensures cursor < count*8 || cursor-count*8 < floor;
lemma fn call_argument_underflow_order(cursor,floor,count) {}

// The available-argument span directly yields the saved-cursor invariant that
// call entry needs: the new floor stays nonnegative and at or above the caller
// floor. The saved cursor is bound to a word and the available-span sum is
// stated in both operand orders so the checker compares the exact bounded
// difference instead of re-searching the compound expression.
requires cursor >= 0 && cursor <= 524288;
requires floor >= 0 && floor <= cursor;
requires count >= 0 && count <= 4096;
requires count*8 <= cursor-floor;
ensures count*8 <= cursor && cursor-count*8 >= floor;
lemma fn call_argument_accept_order(cursor,floor,count) {
    let rest=cursor-count*8;
    assert count*8+floor <= cursor;
    assert floor+count*8 <= cursor;
    assert rest >= floor;
}

// Both directions of the capacity/saved-cursor bridge, composed from the two
// checked order lemmas. Call entry applies this to the proved capacity
// contract: acceptance is exactly the condition under which the new saved
// floor is a bounded operand position inside the caller's frame.
requires cursor >= 0 && cursor <= 524288;
requires floor >= 0 && floor <= cursor;
requires count >= 0 && count <= 4096;
ensures (count*8 <= cursor-floor) == (count*8 <= cursor && cursor-count*8 >= floor);
lemma fn call_argument_capacity_equivalence(cursor,floor,count) {
    if count*8 > cursor-floor {
        call_argument_underflow_order(cursor,floor,count);
    }else {
        call_argument_accept_order(cursor,floor,count);
    }
}

// Minimal concrete witness, matching the native call-entry regression.
requires vm_frames == 8192 && vm_depth == 2 && vm_sp == 16 && vm_local_top == 16 && vm_error == 0;
requires readable_bytes(vm_frames,40960);
requires load64(vm_frames+64) == 16;
reads vm_depth,vm_frames,vm_sp,vm_local_top,vm_error,bytes(vm_frames,40960);
modifies vm_error;
ensures result == 0 && vm_error == 9;
fn call_rejects_locked_operands() {return vm_call_capacity(1,1);}

// Both resources fit exactly: one argument is available above the caller
// floor and the final local word ends at the buffer limit.
requires vm_frames == 8192 && vm_depth == 2 && vm_sp == 24 && vm_local_top == 8388600 && vm_error == 0;
requires readable_bytes(vm_frames,40960);
requires load64(vm_frames+64) == 16;
reads vm_depth,vm_frames,vm_sp,vm_local_top,vm_error,bytes(vm_frames,40960);
ensures result == 1 && vm_error == 0;
fn call_accepts_exact_fit() {return vm_call_capacity(1,1);}

// A malformed negative arity is rejected before reading any VM metadata.
requires count < 0;
reads vm_error;
modifies vm_error;
ensures result == 0 && vm_error == 9;
fn call_rejects_negative_count(count,slots) {return vm_call_capacity(count,slots);}

requires vm_depth == 0;
requires vm_sp >= 0 && vm_sp <= 524288;
requires vm_local_top >= 0 && vm_local_top <= 8388608;
requires vm_error == 0;
reads vm_depth,vm_sp,vm_local_top,vm_error;
modifies vm_error;
ensures result == 0 || result == 1;
ensures result == 0 || vm_error == 0;
ensures result == 1 || vm_error == 9;
ensures (result == 1) == (count >= 0 && count <= slots && slots <= 4096 && count*8 <= vm_sp && vm_local_top+slots*8 <= 8388608);
fn call_capacity_unframed(count,slots) {return vm_call_capacity(count,slots);}

// Complete framed capacity predicate, including acceptance. Rejecting every
// call cannot satisfy this checked profile; exact resource fits are accepted.
requires vm_depth >= 1 && vm_depth <= 1023;
requires vm_sp >= 0 && vm_sp <= 524288;
requires vm_local_top >= 0 && vm_local_top <= 8388608;
requires vm_error == 0;
requires readable_bytes(vm_frames,40960);
requires readable_bytes(vm_frames+(vm_depth-1)*40+24,8);
requires load64(vm_frames+(vm_depth-1)*40+24) >= 0 && load64(vm_frames+(vm_depth-1)*40+24) <= vm_sp;
reads vm_depth,vm_frames,vm_sp,vm_local_top,vm_error,bytes(vm_frames+(vm_depth-1)*40+24,8);
modifies vm_error;
ensures result == 0 || result == 1;
ensures result == 0 || vm_error == 0;
ensures result == 1 || vm_error == 9;
ensures (result == 1) == (count >= 0 && count <= slots && slots <= 4096 && count*8 <= vm_sp-load64(vm_frames+(vm_depth-1)*40+24) && vm_local_top+slots*8 <= 8388608);
fn call_capacity_framed(count,slots) {
    proof {
        assert vm_depth != 0;
    }
    return vm_call_capacity(count,slots);
}
