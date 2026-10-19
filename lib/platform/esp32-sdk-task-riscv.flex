import "esp32-sdk-riscv-clock.flex";
import "esp32-sdk-riscv-tls.flex";
import "esp32-sdk-riscv-reent.flex";
// C3/C6 ILP32, no FPU or Xtensa register windows. MIE is mstatus bit3.
fn esp_sdk_irq_blocked(ps) {return !(ps&8);}
fn esp_sdk_task_unmask() {let ps=esp32_irq_save();return esp32_irq_restore(ps|8);}
fn esp_sdk_context_init(task,stack,size) {
    let top=esp_sdk_tls_copy(task,stack,size);if top<0 {return top;}top=top-16;store64(top,task);esp32_store32(task+8,top);esp32_store32(task+256,esp32_callback(esp_sdk_task_entry));esp32_store32(task+272,0);esp32_store32(task+304,stack);return esp_sdk_reent_create(task);
}
