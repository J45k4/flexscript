import "../../lib/platform/esp32c3-atomics.flex";
import "../../lib/platform/esp32c3-sdk-preempt.flex";
fn atom_call(function){return esp32_call32(function,0,0,0,0,0,0,0,0);}
fn atom_irq(source){if source!=-1{return 1;}return atom_call(esp32_external("atomic_interrupt"));}
fn atom_pause(a,b,c,d,e,f,g,h){if a==3{esp32_irq_raise(128);}return esp_sdk_yield();}
fn main(){
    if esp_atomics_bind()||atom_call(esp32_external("atomic_basic")){return 1;}
    if (esp32_state()==0x3fc90000 || esp32_state()==0x40810000) && atom_call(esp32_external("atomic_cache_probe")){return 9;}
    let arena=esp_sdk_heap_min();if esp_sdk_heap_init(arena,esp_sdk_heap_max()-arena)||esp_sdk_task_init(){return 2;}
    if esp_irq_software(esp32_iram_callback(atom_irq)){return 3;}esp_sdk_task_unmask();if atom_call(esp32_external("atomic_basic")){return 4;}
    esp32_callback32(atom_pause);let before=esp_sdk_heap_free();if esp_sdk_preempt_start(1000){return 5;}
    let a=esp_sdk_task_create(esp32_external("atomic_worker"),1,8192,0);let b=esp_sdk_task_create(esp32_external("atomic_worker"),2,8192,0);if !a||!b{return 6;}
    while load64(a+544)!=2||load64(b+544)!=2{esp_sdk_yield();}
    if esp_sdk_task_reap(a)||esp_sdk_task_reap(b)||esp_sdk_heap_free()!=before||esp_sdk_preempt_stop(){return 7;}
    if atom_call(esp32_external("atomic_result")){return 8;}return 0;
}
