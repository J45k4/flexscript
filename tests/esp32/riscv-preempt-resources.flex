import "../../lib/platform/esp32c3-sdk-preempt.flex";
fn unrelated_irq(source) {return 0;}
fn main() {
 if esp_sdk_preempt_start(1000)!= -16 {return 1;}
 if esp_sdk_heap_init(0x3fcb8000,32768) || esp_sdk_task_init() {return 2;}esp_irq_enable();
 if esp_sdk_preempt_start(999)!= -22 || esp_sdk_preempt_start(1000001)!= -22 || esp_sdk_preempt_enabled {return 3;}
 let base=esp_timer_base(0);let source=esp_timer_source(0);let route=esp_sdk_preempt_route();let heap=esp32_load32(esp32_state());
 if esp_irq_attach(source,esp32_callback(unrelated_irq)) || esp_sdk_preempt_start(1000)!= -16 || esp_sdk_preempt_enabled {return 4;}esp_irq_detach(source);
 let config=esp32_load32(base);esp32_store32(base,config|(1<<31));if esp_sdk_preempt_start(1000)!= -16 {return 5;}esp32_store32(base,config);
 let enabled=esp32_load32(base+0x70);esp32_store32(base+0x70,enabled|1);if esp_sdk_preempt_start(1000)!= -16 {return 6;}esp32_store32(base+0x70,enabled);
 // An event with its peripheral enable masked still belongs to the old user.
 if esp_timer_init(0,40,1) || esp_timer_alarm(0,1000,0) || esp_timer_start(0) {return 7;}esp_reg_update(base+0x70,1,0);
 let start=esp32_cycles();while !esp_timer_pending(0) {if ((esp32_cycles()-start)&4294967295)>100000000 {return 8;}}esp_timer_stop(0);
 if esp_sdk_preempt_start(1000)!= -16 {return 9;}esp_timer_ack(0,0);
 let repeat=0;while repeat<6 {
  esp_timer_init(0,77,1);esp_timer_set(0,55);esp32_store32(base+16,1234);esp32_store32(base+20,9);esp32_store32(base+24,88);esp32_store32(base+28,7);esp32_store32(route,3);esp32_irq_mask(10);
  let saved_config=esp32_load32(base);let ps=esp32_irq_save();esp32_irq_restore(ps|8);
  if esp_sdk_preempt_start(1000) || esp_sdk_preempt_start(1000)!= -16 {return 10;}
  let ticks=esp_sdk_preempt_ticks;start=esp32_cycles();while esp_sdk_preempt_ticks<ticks+2 {if ((esp32_cycles()-start)&4294967295)>100000000 {return 11;}}
  if esp_sdk_preempt_stop() || esp_sdk_preempt_stop() {return 12;}
  if esp32_load32(base)!=saved_config || esp_timer_read(0)!=55 || esp32_load32(base+16)!=1234 || esp32_load32(base+20)!=9 || esp32_load32(base+24)!=88 || esp32_load32(base+28)!=7 || esp32_load32(route)!=3 || esp32_irq_enabled()!=10 || esp_irq_count || esp_timer_pending(0) {return 13;}
  repeat=repeat+1;
 }
 if esp_sdk_preempt_enabled || esp_sdk_reschedule_requested {return 14;}return 0;
}
