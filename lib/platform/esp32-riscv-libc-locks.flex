// Dynamic newlib locks: ESP-IDF v5.5.1 legacy and retargetable ILP32 ABIs.
// Import the chip wrapper and call esp_libc_locks_bind before linking C users.
// These handles contain SDK mutexes, not FreeRTOS StaticSemaphore_t objects.
// Optional stdio supplies static-object aliases; ROM common overrides are separate.
global esp_libc_static_locks=0;
global esp_libc_static_normal=0;
global esp_libc_static_recursive=0;
global esp_libc_boot_locks=0;
global esp_libc_boot_used=0;
global esp_libc_rom_alias=0;
fn esp_libc_static_kind(handle) {let i=0;while esp_libc_static_locks && i<9 {if load64(esp_libc_static_locks+i*16)==handle {return load64(esp_libc_static_locks+i*16+8);}i=i+1;}if esp_libc_rom_alias {if esp32_call(esp_libc_rom_alias,handle) {return 3;}}return 0;}
fn esp_libc_lock_fault() {
    // A void libc locking failure must never return as if exclusion succeeded.
    // The checked C-call intrinsic rejects this null target before any call.
    esp32_call32(0,0,0,0,0,0,0,0,0);return -1;
}
fn esp_libc_lock_context() {
    if !esp_riscv_ready() || esp32_load32(esp32_state()+16) {return esp_libc_lock_fault();}return 0;
}
fn esp_libc_lock_storage(slot) {
    if !slot || (slot&3) || !esp_buffer_valid(slot,4) {return esp_libc_lock_fault();}return slot;
}
fn esp_libc_lock_handle(handle,recursive) {
    let kind=esp_libc_static_kind(handle);if kind {if kind!=3 {if kind!=recursive+1 {return esp_libc_lock_fault();}}handle=esp_libc_static_normal;if recursive {handle=esp_libc_static_recursive;}}
    let header=esp_sdk_header(handle);
    if !header || esp32_load32(header+8)!=32 || load64(handle+24)!=0x4c494243 || load64(handle+16)!=recursive {return esp_libc_lock_fault();}return handle;
}
fn esp_libc_lock_init(slot,recursive) {
    esp_libc_lock_context();esp_libc_lock_storage(slot);let ps=esp32_irq_save();let handle=0;
    if esp_libc_boot_locks {if !recursive || esp_libc_boot_used>=3 {return esp_libc_lock_fault();}handle=load64(esp_libc_boot_locks+esp_libc_boot_used*8);esp_libc_boot_used=esp_libc_boot_used+1;}else {handle=esp_sdk_mutex_create(recursive);}
    if !handle {esp32_irq_restore(ps);return esp_libc_lock_fault();}
    store64(handle+24,0x4c494243);esp32_store32(slot,handle);esp32_irq_restore(ps);return 0;
}
fn esp_libc_lock_close(handle,recursive) {
    esp_libc_lock_context();if !handle {return 0;}if esp_libc_static_kind(handle) {return esp_libc_lock_fault();}let ps=esp32_irq_save();handle=esp_libc_lock_handle(handle,recursive);
    if load64(handle) || load64(handle+8) {esp32_irq_restore(ps);return esp_libc_lock_fault();}
    store64(handle+24,0);esp_sdk_free(handle);esp32_irq_restore(ps);return 0;
}
fn esp_libc_lock_close_slot(slot,recursive) {
    esp_libc_lock_context();esp_libc_lock_storage(slot);let ps=esp32_irq_save();esp_libc_lock_close(esp32_load32(slot),recursive);esp32_store32(slot,0);esp32_irq_restore(ps);return 0;
}
fn esp_libc_lock_acquire(handle,recursive,waiting) {
    esp_libc_lock_context();handle=esp_libc_lock_handle(handle,recursive);if !esp_sdk_current {return 0;}
    if waiting {if !esp_sdk_mutex_lock(handle) {return esp_libc_lock_fault();}return 0;}
    let ps=esp32_irq_save();let owner=load64(handle);
    if !owner || (owner==esp_sdk_current && recursive) {store64(handle,esp_sdk_current);store64(handle+8,load64(handle+8)+1);esp32_irq_restore(ps);return 0;}
    esp32_irq_restore(ps);return -1;
}
fn esp_libc_lock_acquire_slot(slot,recursive,waiting) {
    esp_libc_lock_context();esp_libc_lock_storage(slot);let ps=esp32_irq_save();let handle=esp32_load32(slot);
    if !handle && !esp_sdk_current {esp32_irq_restore(ps);return 0;}
    if !handle {esp_libc_lock_init(slot,recursive);handle=esp32_load32(slot);}
    esp32_irq_restore(ps);return esp_libc_lock_acquire(handle,recursive,waiting);
}
fn esp_libc_lock_release(handle,recursive) {
    esp_libc_lock_context();handle=esp_libc_lock_handle(handle,recursive);if !esp_sdk_current {return 0;}
    if !esp_sdk_mutex_unlock(handle) {return esp_libc_lock_fault();}return 0;
}
fn esp_libc_lock_release_slot(slot,recursive) {
    esp_libc_lock_context();esp_libc_lock_storage(slot);if !esp_sdk_current {return 0;}return esp_libc_lock_release(esp32_load32(slot),recursive);
}
fn _lock_init(a,b,c,d,e,f,g,h) {return esp_libc_lock_init(a,0);}
fn _lock_init_recursive(a,b,c,d,e,f,g,h) {return esp_libc_lock_init(a,1);}
fn _lock_close(a,b,c,d,e,f,g,h) {return esp_libc_lock_close_slot(a,0);}
fn _lock_close_recursive(a,b,c,d,e,f,g,h) {return esp_libc_lock_close_slot(a,1);}
fn _lock_acquire(a,b,c,d,e,f,g,h) {return esp_libc_lock_acquire_slot(a,0,1);}
fn _lock_acquire_recursive(a,b,c,d,e,f,g,h) {return esp_libc_lock_acquire_slot(a,1,1);}
fn _lock_try_acquire(a,b,c,d,e,f,g,h) {return esp_libc_lock_acquire_slot(a,0,0);}
fn _lock_try_acquire_recursive(a,b,c,d,e,f,g,h) {return esp_libc_lock_acquire_slot(a,1,0);}
fn _lock_release(a,b,c,d,e,f,g,h) {return esp_libc_lock_release_slot(a,0);}
fn _lock_release_recursive(a,b,c,d,e,f,g,h) {return esp_libc_lock_release_slot(a,1);}
fn __retarget_lock_init(a,b,c,d,e,f,g,h) {return esp_libc_lock_init(a,0);}
fn __retarget_lock_init_recursive(a,b,c,d,e,f,g,h) {return esp_libc_lock_init(a,1);}
fn __retarget_lock_close(a,b,c,d,e,f,g,h) {return esp_libc_lock_close(a,0);}
fn __retarget_lock_close_recursive(a,b,c,d,e,f,g,h) {return esp_libc_lock_close(a,1);}
fn __retarget_lock_acquire(a,b,c,d,e,f,g,h) {return esp_libc_lock_acquire(a,0,1);}
fn __retarget_lock_acquire_recursive(a,b,c,d,e,f,g,h) {return esp_libc_lock_acquire(a,1,1);}
fn __retarget_lock_try_acquire(a,b,c,d,e,f,g,h) {return esp_libc_lock_acquire(a,0,0);}
fn __retarget_lock_try_acquire_recursive(a,b,c,d,e,f,g,h) {return esp_libc_lock_acquire(a,1,0);}
fn __retarget_lock_release(a,b,c,d,e,f,g,h) {return esp_libc_lock_release(a,0);}
fn __retarget_lock_release_recursive(a,b,c,d,e,f,g,h) {return esp_libc_lock_release(a,1);}
fn esp_libc_locks_bind() {
    esp_libc_lock_context();
    esp32_callback32(_lock_init);esp32_callback32(_lock_init_recursive);esp32_callback32(_lock_close);esp32_callback32(_lock_close_recursive);
    esp32_callback32(_lock_acquire);esp32_callback32(_lock_acquire_recursive);esp32_callback32(_lock_try_acquire);esp32_callback32(_lock_try_acquire_recursive);esp32_callback32(_lock_release);esp32_callback32(_lock_release_recursive);
    esp32_callback32(__retarget_lock_init);esp32_callback32(__retarget_lock_init_recursive);esp32_callback32(__retarget_lock_close);esp32_callback32(__retarget_lock_close_recursive);
    esp32_callback32(__retarget_lock_acquire);esp32_callback32(__retarget_lock_acquire_recursive);esp32_callback32(__retarget_lock_try_acquire);esp32_callback32(__retarget_lock_try_acquire_recursive);esp32_callback32(__retarget_lock_release);esp32_callback32(__retarget_lock_release_recursive);return 0;
}
