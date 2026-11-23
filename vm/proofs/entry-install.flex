import "../core-buffers.flex";
import "../call-frame.flex";
import "call-frame-memory.flex";

// The frame-install stage on the initialized core buffers. The zero-cursor
// state satisfies the installer's cursor and record premises, and the
// production installer writes the five saved fields and advances the local
// cursors by the callee's slot count. This is the buffer-side link from
// initialization to the checked frame-save stage.
requires vm_heap_limit >= 4096 && vm_heap_limit <= 1000000000;
requires vm_depth == 0 && vm_local_base == 0 && vm_local_top == 0;
requires count >= 0 && count <= slots && slots <= 4096 && count*8 <= vm_sp && vm_sp <= 524288;
requires vm_local_top+slots*8 <= 8388608;
modifies vm_heap,vm_stack,vm_local_memory,vm_frames,vm_local_base,vm_local_top;
ensures result == 0 || result == 1;
ensures result == 0 || (load64(vm_frames) == return_pc && load64(vm_frames+8) == old(vm_local_base) && load64(vm_frames+16) == old(vm_local_top));
ensures result == 0 || (load64(vm_frames+24) == vm_sp-count*8 && load64(vm_frames+32) == index);
ensures result == 0 || (vm_local_base == old(vm_local_top) && vm_local_top == old(vm_local_top)+slots*8);
fn install_frame_after_core_init(count,slots,index,return_pc) {
    vm_allocate_core_buffers();
    if vm_heap<0 || vm_stack<0 || vm_local_memory<0 || vm_frames<0 {return 0;}
    proof {call_frame_record_writable(vm_frames,vm_depth);}
    vm_install_call_frame(index,return_pc,count,slots);
    return 1;
}

