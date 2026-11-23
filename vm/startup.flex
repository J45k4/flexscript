import "core-buffers.flex";

global vm_time=0;
global vm_path=0;
global vm_open_how=0;
global vm_poll_records=0;
global vm_file_stat=0;
global vm_fds=0;
global vm_stdin=0;
global vm_jit_cache=0;
global vm_jit_context=0;

fn vm_allocate_descriptor_table() {
    vm_fds=alloc(67*8);
    return 0;
}

fn vm_allocate_auxiliary_buffers(function_capacity) {
    vm_time=alloc(16);vm_path=alloc(4096);vm_open_how=alloc(24);
    vm_allocate_descriptor_table();
    vm_jit_cache=alloc((function_capacity+2048)*32);vm_jit_context=alloc(64);
    vm_poll_records=alloc(67*8);
    vm_file_stat=alloc(144);
    return 0;
}

// The bounded descriptor initialization. The table is already writable and
// the loop writes stay inside it. The VM gate's startup profile attaches the
// observed-slot value contract on top of these premises.
requires writable_bytes(vm_fds,536);
modifies bytes(vm_fds,536);
ensures writable_bytes(vm_fds,536);
fn vm_initialize_fd_table() {
    let i=0;
    invariant i>=0 && i<=67;
    invariant writable_bytes(vm_fds,536);
    decreases 67-i;
    while i<67 {
        store64(vm_fds+i*8,-1);
        i=i+1;
    }
    if vm_stdin {store64(vm_fds,0);}
    store64(vm_fds+8,1);
    store64(vm_fds+16,2);
    return 0;
}

fn vm_host_fd(fd) {
    if fd<0 || fd>=67 {return -1;}return load64(vm_fds+fd*8);
}

// Establish the memory state shared by interpreter and JIT startup.
fn vm_initialize_buffers(function_capacity) {
    vm_allocate_core_buffers();
    vm_allocate_auxiliary_buffers(function_capacity);
    if vm_heap<0 || vm_stack<0 || vm_local_memory<0 || vm_frames<0 || vm_time<0
        || vm_path<0 || vm_open_how<0 || vm_fds<0 || vm_jit_cache<0 || vm_jit_context<0
        || vm_poll_records<0 || vm_file_stat<0 {return 0;}
    vm_initialize_fd_table();
    return 1;
}
