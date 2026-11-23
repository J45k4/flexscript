import "../startup.flex";
import "call-frame-memory.flex";

// Milestone-1 call-entry state link. The checked startup theorem establishes
// the writable extents and pairwise separation of the operand stack, local
// memory, and frame buffer, and preserves the incoming cursors. These roots
// derive from that initialized state every buffer premise of the accepted
// call-entry path that does not involve compiler metadata. Parser
// establishment of the function-record values remains a separate obligation.
//
// The stage wrappers carry the same contracts the VM gate's generated startup
// profile attaches to the production stages, so each stage is summarized at
// its call site instead of being re-inlined into every root. The entry root
// consumes the initialized-state theorem's contract; the fully inlined
// single-circuit composition of startup and the local-copy loop still exceeds
// the engine's maximum circuit and remains open with the framed entry design.

// Auxiliary buffers: fresh writable regions for the host-facing VM state.
// The descriptor table's separation from the core guest buffers is checked by
// the VM gate's startup profile; this bundle establishes the extents that the
// call-entry path consumes.
requires function_capacity >= 0 && function_capacity <= 16384;
requires vm_heap<0 || writable_bytes(vm_heap,vm_heap_limit);
requires vm_stack<0 || writable_bytes(vm_stack,524288);
requires vm_local_memory<0 || writable_bytes(vm_local_memory,8388608);
requires vm_frames<0 || writable_bytes(vm_frames,40960);
modifies vm_time,vm_path,vm_open_how,vm_fds,vm_jit_cache,vm_jit_context,vm_poll_records,vm_file_stat;
ensures vm_time<0 || writable_bytes(vm_time,16);
ensures vm_path<0 || writable_bytes(vm_path,4096);
ensures vm_open_how<0 || writable_bytes(vm_open_how,24);
ensures vm_fds<0 || writable_bytes(vm_fds,536);
ensures vm_jit_cache<0 || writable_bytes(vm_jit_cache,(function_capacity+2048)*32);
ensures vm_jit_context<0 || writable_bytes(vm_jit_context,64);
ensures vm_poll_records<0 || writable_bytes(vm_poll_records,536);
ensures vm_file_stat<0 || writable_bytes(vm_file_stat,144);
fn entry_state_allocate_auxiliary_buffers(function_capacity) {
    return vm_allocate_auxiliary_buffers(function_capacity);
}

// The descriptor table initialization: the bounded loop writes stay inside
// the fresh table and preserve its writability. The production body writes
// unconditionally, so the table must already be writable.
requires writable_bytes(vm_fds,536);
modifies vm_fds,bytes(vm_fds,536);
ensures writable_bytes(vm_fds,536);
fn entry_state_initialize_fd_table() {
    return vm_initialize_fd_table();
}

// Shared startup on the zero-cursor initial state, up to the descriptor
// table. On success the three guest buffers are writable and separated and
// the zero cursors survive unchanged. The descriptor-table stage writes only
// its own fresh allocation; its checked wrapper root above and the VM gate's
// startup profile cover that stage, so this root stops after the buffers the
// call-entry path consumes.
requires vm_heap_limit >= 4096 && vm_heap_limit <= 1000000000;
requires function_capacity >= 0 && function_capacity <= 16384;
requires vm_depth == 0 && vm_sp == 0 && vm_local_base == 0 && vm_local_top == 0;
modifies vm_heap,vm_stack,vm_local_memory,vm_frames,vm_time,vm_path,vm_open_how,vm_fds,vm_jit_cache,vm_jit_context,vm_poll_records,vm_file_stat;
ensures result == 0 || result == 1;
ensures result == 0 || writable_bytes(vm_stack,524288);
ensures result == 0 || writable_bytes(vm_local_memory,8388608);
ensures result == 0 || writable_bytes(vm_frames,40960);
ensures result == 0 || !(vm_stack>0 && vm_local_memory>0) || disjoint_bytes(vm_stack,524288,vm_local_memory,8388608);
ensures result == 0 || !(vm_stack>0 && vm_frames>0) || disjoint_bytes(vm_stack,524288,vm_frames,40960);
ensures result == 0 || !(vm_local_memory>0 && vm_frames>0) || disjoint_bytes(vm_local_memory,8388608,vm_frames,40960);
ensures vm_depth == old(vm_depth) && vm_sp == old(vm_sp);
ensures vm_local_base == old(vm_local_base) && vm_local_top == old(vm_local_top);
ensures vm_error == old(vm_error) && vm_finished == old(vm_finished);
fn initialized_call_entry_state(function_capacity) {
    vm_allocate_core_buffers();
    if vm_heap<0 || vm_stack<0 || vm_local_memory<0 || vm_frames<0 {return 0;}
    entry_state_allocate_auxiliary_buffers(function_capacity);
    return 1;
}

