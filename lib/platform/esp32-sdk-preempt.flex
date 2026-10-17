import "esp32-sdk-task.flex";
import "esp32-irq.flex";
import "esp32-sdk-preempt-core.flex";
fn esp_sdk_preempt_enable_reg() {return 0x3ff60098;}
fn esp_sdk_preempt_route() {return 0x3ff00150;}
