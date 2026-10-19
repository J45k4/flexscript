import "../../lib/platform/esp32c3-xip.flex";
import "../../lib/platform/esp32c3-atomics.flex";
import "../../lib/platform/esp32c3-sdk-preempt.flex";
global vendor_sum=0;global vendor_error=0;
fn vTaskDelay(a,b,c,d,e,f,g,h){return esp_sdk_delay(a);}
fn vendor_worker(a,b,c,d,e,f,g,h){let i=0;while i<50{
 esp32_call32(esp32_external("eloop_lifecycle_lock"),0,0,0,0,0,0,0,0);
 if load8(esp32_external("eloop_lifecycle_busy"))!=1{vendor_error=1;return 0;}vendor_sum=vendor_sum+a;esp_sdk_yield();
 esp32_call32(esp32_external("eloop_lifecycle_unlock"),0,0,0,0,0,0,0,0);i=i+1;
 }return 0;}
fn main(){
 if esp_atomics_bind(){return 1;}let arena=esp_sdk_heap_min();if esp_sdk_heap_init(arena,esp_sdk_heap_max()-arena)||esp_sdk_task_init(){return 2;}esp32_callback32(vTaskDelay);esp_sdk_task_unmask();
 if esp_sdk_preempt_start(1000){return 3;}let before=esp_sdk_heap_free();let a=esp_sdk_task_create(esp32_callback32(vendor_worker),1,8192,0);let b=esp_sdk_task_create(esp32_callback32(vendor_worker),2,8192,0);if !a||!b{return 4;}
 while load64(a+544)!=2||load64(b+544)!=2{esp_sdk_yield();}if esp_sdk_task_reap(a)||esp_sdk_task_reap(b)||esp_sdk_heap_free()!=before||esp_sdk_preempt_stop(){return 5;}
 if vendor_error||vendor_sum!=150||load8(esp32_external("eloop_lifecycle_busy")){return 6;}return 0;
}
