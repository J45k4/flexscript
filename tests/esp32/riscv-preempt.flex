import "../../lib/platform/esp32c3-sdk-preempt.flex";
global done=0;
global error=0;
fn worker(a,b,c,d,e,f,g,h) {let v=0x8877665544332211;let start=esp_sdk_preempt_ticks;while esp_sdk_preempt_ticks<start+5 {if v!=0x8877665544332211 {error=1;}v=v+1;v=v-1;}done=done+1;return 0;}
fn main() {esp_irq_enable();if esp_sdk_heap_init(0x3fcb8000,32768) || esp_sdk_task_init() {return 1;}if !esp_sdk_task_create(esp32_callback32(worker),0,8192,0) {return 2;}if esp_sdk_preempt_start(1000) {return 3;}let start=esp32_cycles();while !done {if ((esp32_cycles()-start)&4294967295)>200000000 {return 4;}}if esp_sdk_preempt_stop() {return 5;}if error || !esp_sdk_preempt_switches {return 6;}return 0;}
