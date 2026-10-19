import "esp32s3-timer.flex";
import "esp32-sdk-task-xtensa.flex";
import "esp32-sdk-task-core.flex";
fn esp_sdk_task_profile_valid() {return esp32_state()==0x3fca8000 || esp32_state()==0x3fcb0000 || esp32_state()==0x3fcc0000;}
