import "esp32c6-sdk-task.flex";
import "esp32c6-irq.flex";
import "esp32c6-timer.flex";
import "esp32-sdk-preempt-core.flex";
fn esp_sdk_preempt_timer() {return 0;}
fn esp_sdk_preempt_interrupt_bit() {return 1;}
fn esp_sdk_preempt_timer_init() {return esp_timer_init(0,40,1);}
fn esp_sdk_preempt_enable_reg() {return esp_timer_base(0)+0x70;}
fn esp_sdk_preempt_route() {return esp_irq_matrix()+esp_timer_source(0)*4;}
