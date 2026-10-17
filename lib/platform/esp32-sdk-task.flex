import "esp32-timer.flex";
import "esp32-sdk-task-core.flex";
fn esp_sdk_task_profile_valid() {return esp32_state()==0x3ffb0000 || esp32_state()==0x3ffc0000;}
