import "../../lib/platform/esp32c3-libc.flex";
import "../../lib/platform/esp32c3-irq.flex";
global li_done=0;global li_live=0;global li_error=0;global li_hits=0;
fn libc_pause(a,b,c,d,e,f,g,h){return 0;}
fn li_worker(a,b,c,d,e,f,g,h){return 0;}
fn li_irq(source){
 if !esp_sdk_current {let before=esp_sdk_heap_free();if esp_sdk_task_init()!=-16||esp_sdk_current||esp_sdk_heap_free()!=before{li_error=3;}li_hits=li_hits+1;return 0;}
 let before=esp_sdk_heap_free();let next=load64(esp_sdk_current+536);
 if esp_sdk_task_init()!=-16||esp_sdk_task_create(esp32_callback32(li_worker),0,4096,0)||esp_sdk_task_delete(li_live)!=-16||esp_sdk_task_reap(li_done)!=-16{li_error=1;}
 if esp_sdk_heap_free()!=before||load64(esp_sdk_current+536)!=next||load64(li_live+544)!=1||load64(li_done+544)!=2{li_error=2;}li_hits=li_hits+1;return 0;
}
fn main(){
 if esp_sdk_heap_init(0x3fcb8000,32768)||esp_libc_reent_init(){return 1;}esp32_callback32(libc_pause);esp_irq_software(esp32_callback(li_irq));esp32_irq_raise(128);esp_irq_enable();if li_hits!=1||li_error||esp_sdk_task_init(){return 1;}let before=esp_sdk_heap_free();
 li_done=esp_sdk_task_create(esp32_callback32(li_worker),0,4096,1);if !li_done{return 2;}while load64(li_done+544)!=2{esp_sdk_yield();}
 li_live=esp_sdk_task_create(esp32_callback32(li_worker),0,4096,0);if !li_live{return 3;}esp_irq_software(esp32_callback(li_irq));esp32_irq_raise(128);esp_irq_enable();
 if li_hits!=2||li_error{return 4;}if esp_sdk_task_reap(li_done)||esp_sdk_task_delete(li_live)||esp_sdk_task_reap(li_live)||esp_sdk_heap_free()!=before{return 5;}return 0;
}
