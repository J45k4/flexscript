import "../../lib/platform/esp32c3-sdk-sync.flex";
fn main(){
 if esp_sdk_heap_init(0x3fcb8000,32768){return 1;}let free=esp_sdk_heap_free();let base=esp_sdk_clock_base();let config=esp32_load32(base);let enable=esp32_load32(base+0x70);
 esp32_store32(base,config|(1<<31));if esp_sdk_task_init()!=-16||esp_sdk_current||esp_sdk_heap_free()!=free{return 2;}esp32_store32(base,config);
 esp32_store32(base+0x70,enable|1);if esp_sdk_task_init()!=-16||esp_sdk_current||esp_sdk_heap_free()!=free{return 3;}esp32_store32(base+0x70,enable);
 if esp_sdk_task_init()||esp_sdk_task_init()!=-16{return 4;}let ps=esp32_irq_save();if esp_sdk_can_block()||esp_sdk_yield()!=-16||esp_sdk_delay(1)!=-16||esp_sdk_task_delete(0)!=-16{return 5;}
 let sem=esp_sdk_sem_create(1,0);if !sem||esp_sdk_sem_take(sem,100){return 6;}esp_sdk_task_unmask();if !esp_sdk_can_block(){return 7;}
 esp32_store32(esp32_state()+16,1);if esp_sdk_can_block()||esp_sdk_yield()!=-16||esp_sdk_delay(1)!=-16{return 8;}esp32_store32(esp32_state()+16,0);
 let start=esp_sdk_now();if esp_sdk_sem_take(sem,2)||esp_sdk_now()-start<2000||load64(esp_sdk_current+544)!=1||load64(esp_sdk_current+600){return 9;}
 esp32_irq_restore(ps);return 0;
}
