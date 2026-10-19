// Task-local standard-library state and allocator exports for the pinned
// newlib4.3 ILP32 archive. Standard streams/ROM syscall startup are separate.
fn esp_libc_reent_context() {
    if !esp_libc_main_reent || esp32_load32(esp32_state()+16) {return esp_libc_lock_fault();}return 0;
}
fn esp_libc_reent_pointer(reent) {
    if (reent&3) || !esp_buffer_valid(reent,240) {return esp_libc_lock_fault();}return reent;
}
fn esp_libc_getreent() {
    esp_libc_reent_context();let reent=esp_libc_main_reent;
    if esp_sdk_current && esp_sdk_current!=esp_sdk_tasks {reent=load64(esp_sdk_current+320);}return esp_libc_reent_pointer(reent);
}
fn __getreent(a,b,c,d,e,f,g,h) {return esp_libc_getreent();}
fn esp_libc_errno(reent,error) {esp_libc_reent_pointer(reent);esp32_store32(reent,error);return 0;}
fn esp_libc_malloc(reent,size) {
    esp_libc_reent_context();esp_libc_reent_pointer(reent);let result=esp_sdk_malloc(size);if !result && size {esp_libc_errno(reent,12);}return result;
}
fn esp_libc_calloc(reent,count,size) {
    esp_libc_reent_context();esp_libc_reent_pointer(reent);let result=esp_sdk_calloc(count,size);if !result && count && size {esp_libc_errno(reent,12);}return result;
}
fn esp_libc_realloc(reent,pointer,size) {
    esp_libc_reent_context();esp_libc_reent_pointer(reent);
    if pointer && !esp_sdk_header(pointer) {return esp_libc_lock_fault();}let result=esp_sdk_realloc(pointer,size);if !result && size {esp_libc_errno(reent,12);}return result;
}
fn esp_libc_free(reent,pointer) {
    esp_libc_reent_context();esp_libc_reent_pointer(reent);if esp_sdk_free(pointer) {return esp_libc_lock_fault();}return 0;
}
fn malloc(a,b,c,d,e,f,g,h) {return esp_libc_malloc(esp_libc_getreent(),a);}
fn calloc(a,b,c,d,e,f,g,h) {return esp_libc_calloc(esp_libc_getreent(),a,b);}
fn realloc(a,b,c,d,e,f,g,h) {return esp_libc_realloc(esp_libc_getreent(),a,b);}
fn free(a,b,c,d,e,f,g,h) {return esp_libc_free(esp_libc_getreent(),a);}
fn _malloc_r(a,b,c,d,e,f,g,h) {return esp_libc_malloc(a,b);}
fn _calloc_r(a,b,c,d,e,f,g,h) {return esp_libc_calloc(a,b,c);}
fn _realloc_r(a,b,c,d,e,f,g,h) {return esp_libc_realloc(a,b,c);}
fn _free_r(a,b,c,d,e,f,g,h) {return esp_libc_free(a,b);}
fn __assert_func(a,b,c,d,e,f,g,h) {return esp_libc_lock_fault();}
fn esp_libc_reent_bind(reent) {
    esp_libc_reclaim=esp32_external("_reclaim_reent");esp_libc_main_reent=reent;_impure_ptr=reent;_global_impure_ptr=reent;
    esp32_callback32(__getreent);esp32_callback32(malloc);esp32_callback32(calloc);esp32_callback32(realloc);esp32_callback32(free);
    esp32_callback32(_malloc_r);esp32_callback32(_calloc_r);esp32_callback32(_realloc_r);esp32_callback32(_free_r);esp32_callback32(__assert_func);esp_libc_locks_bind();return 0;
}
fn esp_libc_reent_init() {
    esp_libc_lock_context();if esp_libc_main_reent || esp_sdk_current {return -16;}if !esp_sdk_begin {return -19;}
    let reent=esp_sdk_calloc(1,240);if !reent {return -12;}
    return esp_libc_reent_bind(reent);
}
