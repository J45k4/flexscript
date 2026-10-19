import "../../lib/platform/esp32c3-libc.flex";
import "../../lib/platform/esp32c3-sdk-preempt.flex";
fn libc_pause(a,b,c,d,e,f,g,h){let start=esp32_cycles();while ((esp32_cycles()-start)&4294967295)<320000{}return 0;}
fn main(){
 if esp_sdk_heap_init(0x3fcb8000,32768)||esp_libc_reent_init()||esp_sdk_task_init(){return 1;}esp32_callback32(libc_pause);esp_irq_enable();let before=esp_sdk_heap_free();let identity=esp_libc_getreent();esp_libc_errno(identity,444);
 let a=esp_sdk_task_create(esp32_external("libc_preempt_worker"),1,8192,0);let b=esp_sdk_task_create(esp32_external("libc_preempt_worker"),2,8192,0);if !a||!b||esp_sdk_preempt_start(1000){return 2;}
 let start=esp32_cycles();while load64(a+544)!=2||load64(b+544)!=2 {if ((esp32_cycles()-start)&4294967295)>400000000{return 3;}}
 if esp_sdk_preempt_stop()||esp_sdk_preempt_switches<8{return 4;}if esp_sdk_task_reap(a)||esp_sdk_task_reap(b){return 5;}
 if esp32_call32(esp32_external("libc_status"),0,0,0,0,0,0,0,0)!=2||esp_sdk_heap_free()!=before||esp32_load32(identity)!=444||_impure_ptr!=identity{return 6;}return 0;
}
