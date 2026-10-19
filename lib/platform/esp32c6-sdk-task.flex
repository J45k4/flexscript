import "esp32c6.flex";
import "esp32-sdk-task-riscv.flex";
import "esp32-sdk-task-core.flex";
fn esp_sdk_task_profile_valid() {return esp_riscv_ready();}
