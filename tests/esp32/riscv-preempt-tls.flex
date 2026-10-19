import "../../lib/platform/esp32c3-sdk-preempt.flex";
global tls_irq_error=0;
fn tls_timer_irq(source) {if esp_timer_pending(0) {let result=esp32_call32(esp32_external("preempt_tls_irq"),0,0,0,0,0,0,0,0);if result {tls_irq_error=result;}}return esp_sdk_preempt_tick(source);}
fn main() {
 if esp_sdk_heap_init(0x3fcb8000,32768) || esp_sdk_task_init() {return 1;}esp_irq_enable();
 let one=esp_sdk_task_create(esp32_external("preempt_tls_run"),17,8192,0);let two=esp_sdk_task_create(esp32_external("preempt_tls_run"),29,8192,0);if !one || !two {return 2;}
 if esp_sdk_preempt_start(1000) || esp_irq_attach(esp_timer_source(0),esp32_callback(tls_timer_irq)) {return 3;}
 let result=esp32_call32(esp32_external("preempt_tls_run"),99,0,0,0,0,0,0,0);if result {return 10+result;}
 let start=esp32_cycles();while load64(one+544)!=2 || load64(two+544)!=2 {if ((esp32_cycles()-start)&4294967295)>200000000 {return 4;}}
 if esp_sdk_preempt_stop() || tls_irq_error || esp_sdk_preempt_switches<4 {return 5;}return esp32_call32(esp32_external("preempt_tls_result"),0,0,0,0,0,0,0,0);
}
