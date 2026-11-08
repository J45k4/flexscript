import "thread/atomic.flex";
import "thread/mutex.flex";
lowering thread_clone_native "linux.thread.clone" "native-x86_64";
fn thread_clone_native(record,stack_top) {return -38;}

// Handle: callback, argument, kernel TID, result, stack mapping, mapping length,
// join state (0 available, 1 joining, 2 joined), reserved. One mapping/handle;
// there is no process-global allocator/cache or TLS dependency in this library.
fn thread_start(callback,argument) {return thread_start_with_stack(callback,argument,1048576);}
fn thread_start_with_stack(callback,argument,stack_bytes) {
    if !thread_supported() {return -38;}
    if callback<=0 || stack_bytes<65536 || stack_bytes>1073741824 {return -22;}
    let size=(stack_bytes+4095)& -4096;let total=size+8192;
    let record=alloc(64);if record<0 {return record;}
    let mapping=syscall(9,0,total,0,34,-1,0);
    if mapping<0 {syscall(11,record,64,0,0,0,0);return mapping;}
    let error=syscall(10,mapping+4096,size,3,0,0,0);
    if error<0 {syscall(11,mapping,total,0,0,0,0);syscall(11,record,64,0,0,0,0);return error;}
    store64(record,callback);store64(record+8,argument);
    store64(record+32,mapping);store64(record+40,total);
    let tid=thread_clone_native(record,mapping+4096+size);
    if tid<0 {syscall(11,mapping,total,0,0,0,0);syscall(11,record,64,0,0,0,0);return tid;}
    return record;
}
// Join waits for kernel-confirmed exit, not merely a userspace "done" flag.
// result_out is zero or a valid writable word, disjoint from the handle/stack.
// A successful join releases the stack; destroy separately releases the handle.
fn thread_join(thread,result_out) {
    if !thread_supported() {return -38;}if thread<=0 {return -22;}
    let tid=atomic_load32(thread+16);
    if tid && tid==syscall(186,0,0,0,0,0,0) {return -35;}
    let state=atomic_compare_exchange32(thread+48,0,1);
    if state==2 {return -22;}if state {return -16;}
    tid=atomic_load32(thread+16);
    while tid {
        // CHILD_CLEARTID uses a shared futex wake, not FUTEX_WAKE_PRIVATE.
        let error=syscall(202,thread+16,0,tid,0,0,0);
        if error<0 && error!= -11 && error!= -4 {atomic_exchange32(thread+48,0);return error;}
        tid=atomic_load32(thread+16);
    }
    let error=syscall(11,load64(thread+32),load64(thread+40),0,0,0,0);
    if error<0 {atomic_exchange32(thread+48,0);return error;}
    if result_out {store64(result_out,load64(thread+24));}
    atomic_exchange32(thread+48,2);return 0;
}
// Caller must exclude concurrent join/destroy/access and discard the handle.
fn thread_destroy(thread) {
    if !thread_supported() {return -38;}if thread<=0 {return -22;}
    if atomic_load32(thread+48)!=2 {return -16;}
    return syscall(11,thread,64,0,0,0,0);
}
