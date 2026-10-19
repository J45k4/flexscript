// Xtensa details for the shared cooperative SDK scheduler.
fn esp_sdk_irq_blocked(ps) {return ps&15;}
fn esp_sdk_task_unmask() {return esp32_irq_restore(0);}
fn esp_sdk_clock_init() {esp_timer_init(2,80,0);return esp_timer_start(2);}
fn esp_sdk_clock_now() {return esp_timer_read(2);}
fn esp_sdk_context_init(task,stack,size) {
    let top=stack+size-16;store64(top,task);esp32_store32(task+4,top);esp32_store32(task+256,esp32_callback(esp_sdk_task_entry));esp32_store32(task+264,1);esp32_store32(task+272,15);esp32_store32(task+292,1);esp32_store32(task+304,stack);return 0;
}
fn esp_sdk_stack_bytes(bytes) {return bytes;}
fn esp_sdk_context_free(task) {return 0;}
fn esp_sdk_context_select(task) {return 0;}
