import "esp32-sdk-task.flex";
import "esp32-irq.flex";
import "esp32-sdk-preempt-core.flex";
fn esp_sdk_preempt_enable_reg() {return 0x3ff60098;}
fn esp_sdk_preempt_route() {return 0x3ff00150;}

fn esp_sdk_preempt_timer() {return 3;}
fn esp_sdk_preempt_interrupt_bit() {return 2;}
fn esp_sdk_preempt_timer_init() {return esp_timer_init(3,80,0);}
