// ESP-IDF v5.5.1 / esp-14.2.0_20241119 newlib4.3 ILP32 small, backward-compatible
// reent: sizeof240, alignment4. Independent C target headers verify this ABI.
// SDK TCB context bytes320..327 are architecture-owned and never CPU-saved.
global esp_libc_main_reent=0;
global esp_libc_reclaim=0;
global _impure_ptr=0;
global _global_impure_ptr=0;
global esp_libc_stdio_ready=0;
fn esp_sdk_context_select(task) {
    if esp_libc_main_reent {let reent=esp_libc_main_reent;if task!=esp_sdk_tasks {reent=load64(task+320);}_impure_ptr=reent;}return 0;
}
fn esp_sdk_reent_create(task) {
    if !esp_libc_main_reent {return 0;}let reent=esp_sdk_calloc(1,240);if !reent {return -12;}
    if esp_libc_stdio_ready {let i=4;while i<=12 {esp32_store32(reent+i,esp32_load32(esp_libc_main_reent+i));i=i+4;}esp32_store32(reent+24,1);esp32_store32(reent+40,esp32_load32(esp_libc_main_reent+40));}
    store64(task+320,reent);return 0;
}
fn esp_sdk_context_free(task) {
    let reent=load64(task+320);if !reent {return 0;}
    // The dead task has been unlinked. Reclamation runs in its reaper's task
    // context, before either the reent record or the task stack is released.
    esp32_call32(esp_libc_reclaim,reent,0,0,0,0,0,0,0);store64(task+320,0);esp_sdk_free(reent);return 0;
}
