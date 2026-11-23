import "allocation.flex";
import "operand-stack.flex";
import "frame-state.flex";

// Allocation errors remain in the corresponding globals for vm_initialize.
requires vm_heap_limit>=16 && vm_heap_limit<=1000000000;
reads vm_heap_limit,vm_heap,vm_stack,vm_local_memory,vm_frames;
modifies vm_heap,vm_stack,vm_local_memory,vm_frames;
ensures vm_heap<0 || writable_bytes(vm_heap,vm_heap_limit);
ensures vm_stack<0 || writable_bytes(vm_stack,524288);
ensures vm_local_memory<0 || writable_bytes(vm_local_memory,8388608);
ensures vm_frames<0 || writable_bytes(vm_frames,40960);
ensures vm_frames<0 || fresh_bytes(vm_frames,40960);
ensures !(vm_heap>0 && vm_stack>0) || disjoint_bytes(vm_heap,vm_heap_limit,vm_stack,524288);
ensures !(vm_heap>0 && vm_local_memory>0) || disjoint_bytes(vm_heap,vm_heap_limit,vm_local_memory,8388608);
ensures !(vm_heap>0 && vm_frames>0) || disjoint_bytes(vm_heap,vm_heap_limit,vm_frames,40960);
ensures !(vm_stack>0 && vm_local_memory>0) || disjoint_bytes(vm_stack,524288,vm_local_memory,8388608);
ensures !(vm_stack>0 && vm_frames>0) || disjoint_bytes(vm_stack,524288,vm_frames,40960);
ensures !(vm_local_memory>0 && vm_frames>0) || disjoint_bytes(vm_local_memory,8388608,vm_frames,40960);
fn vm_allocate_core_buffers() {
    vm_heap=alloc(vm_heap_limit);
    proof {
        if vm_heap>0 {assert writable_bytes(vm_heap,vm_heap_limit);}
    }
    vm_stack=alloc(524288);
    proof {
        if vm_heap>0 {assert writable_bytes(vm_heap,vm_heap_limit);}
        if vm_stack>0 {assert writable_bytes(vm_stack,524288);}
    }
    vm_local_memory=alloc(8388608);
    proof {
        if vm_heap>0 {assert writable_bytes(vm_heap,vm_heap_limit);}
        if vm_stack>0 {assert writable_bytes(vm_stack,524288);}
        if vm_local_memory>0 {assert writable_bytes(vm_local_memory,8388608);}
    }
    vm_frames=alloc(1024*40);
    return 0;
}
