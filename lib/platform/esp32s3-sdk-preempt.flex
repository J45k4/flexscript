import "esp32s3-sdk-task.flex";
import "esp32s3-irq.flex";
import "esp32-sdk-preempt-core.flex";
fn esp_sdk_preempt_enable_reg() {return 0x60020070;}
fn esp_sdk_preempt_route() {return 0x600c20d8;}
