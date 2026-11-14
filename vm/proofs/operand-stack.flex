import "../operand-stack.flex";
import "operand-stack-region.flex";

// The caller supplies ownership of the one slot this operation writes.
// The checked region lemma derives that slot grant from a complete stack grant.
requires vm_sp >= 0 && vm_sp <= 524280;
requires vm_error == 0;
requires writable_bytes(vm_stack+vm_sp,8);
reads vm_stack,vm_sp,vm_error,bytes(vm_stack+vm_sp,8);
modifies vm_sp,vm_error,bytes(vm_stack+vm_sp,8);
ensures result == 1;
ensures vm_sp == old(vm_sp)+8 && vm_sp <= 524288;
ensures vm_error == 0;
ensures load64(vm_stack+old(vm_sp)) == old(value);
fn operand_push_slot(value) {return vm_push(value);}

// Overflow must reject without accessing bytes, even without a memory grant.
requires vm_sp == 524288;
reads vm_stack,vm_sp,vm_error;
modifies vm_error;
ensures result == 0 && vm_error == 4;
ensures vm_sp == old(vm_sp);
fn operand_push_full(value) {return vm_push(value);}

// The unframed empty stack must also reject without touching byte memory.
requires vm_depth == 0;
requires vm_sp == 0;
reads vm_stack,vm_sp,vm_error,vm_frames,vm_depth;
modifies vm_error;
ensures result == 0 && vm_sp == 0 && vm_error == 4;
fn operand_pop_empty() {return vm_pop();}

// A nonempty unframed pop composes the checked production read primitive.
requires vm_depth == 0;
requires vm_sp >= 8 && vm_sp <= 524288;
requires vm_error == 0;
requires readable_bytes(vm_stack+(vm_sp-8),8);
reads vm_stack,vm_sp,vm_error,vm_frames,vm_depth,bytes(vm_stack+(vm_sp-8),8);
modifies vm_sp,vm_error;
ensures vm_sp == old(vm_sp)-8 && vm_error == 0;
ensures result == old(load64(vm_stack+(vm_sp-8)));
fn operand_pop_root() {return vm_pop();}

// Reaching the saved frame floor rejects without a grant for stack bytes.
// Ownership of the saved floor field itself is an explicit entry premise.
requires vm_depth >= 1 && vm_depth <= 1024;
requires vm_sp >= 0 && vm_sp <= 524288;
requires readable_bytes(vm_frames+(vm_depth-1)*40+24,8);
requires load64(vm_frames+(vm_depth-1)*40+24) >= vm_sp;
reads vm_stack,vm_sp,vm_error,vm_frames,vm_depth,bytes(vm_frames+(vm_depth-1)*40+24,8);
modifies vm_error;
ensures vm_sp == old(vm_sp) && vm_error == 4 && result == 0;
fn operand_pop_frame_empty() {proof {assert vm_depth != 0;}return vm_pop();}

// Nonempty framed pop, with the actual saved floor and readable old top slot.
// The erased proof establishes strict order separately from heap reasoning.
requires vm_depth >= 1 && vm_depth <= 1024;
requires vm_sp >= 8 && vm_sp <= 524288;
requires vm_error == 0;
requires readable_bytes(vm_frames+(vm_depth-1)*40+24,8);
requires load64(vm_frames+(vm_depth-1)*40+24) >= 0 && load64(vm_frames+(vm_depth-1)*40+24) <= vm_sp-8;
requires readable_bytes(vm_stack+(vm_sp-8),8);
reads vm_stack,vm_sp,vm_error,vm_frames,vm_depth,bytes(vm_stack+(vm_sp-8),8),bytes(vm_frames+(vm_depth-1)*40+24,8);
modifies vm_sp,vm_error;
ensures vm_sp == old(vm_sp)-8 && vm_error == 0;
ensures result == old(load64(vm_stack+(vm_sp-8)));
fn operand_pop_frame() {
    proof {
        operand_pop_floor_order(vm_sp,load64(vm_frames+(vm_depth-1)*40+24));
        assert vm_depth != 0;
    }
    return vm_pop();
}

requires cursor >= 8 && cursor <= 524288;
requires floor >= 0 && floor <= cursor-8;
reads nothing;
modifies nothing;
ensures cursor > floor;
lemma fn operand_pop_floor_order(cursor,floor) {}

// Compose the checked case profiles. Each branch calls the same production
// vm_push exactly once; proof code only establishes the required slot grant.
requires vm_sp >= 0 && vm_sp <= 524288 && (vm_sp & 7) == 0;
requires vm_error == 0;
requires writable_bytes(vm_stack,524288);
reads vm_stack,vm_sp,vm_error,bytes(vm_stack,524288);
modifies vm_sp,vm_error,bytes(vm_stack,524288);
ensures result == 0 || result == 1;
ensures result == 0 || vm_sp == old(vm_sp)+8;
ensures result == 0 || vm_error == 0;
ensures result == 0 || load64(vm_stack+old(vm_sp)) == old(value);
ensures result != 0 || vm_sp == old(vm_sp);
ensures result != 0 || vm_error == 4;
ensures (old(vm_sp)<524288) == (result==1);
fn operand_push_buffer(value) {
    if vm_sp<524288 {
        proof {operand_stack_slot_permission(vm_stack,vm_sp);}
        return operand_push_slot(value);
    }
    return operand_push_full(value);
}
