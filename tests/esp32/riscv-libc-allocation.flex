import "../../lib/platform/esp32c3-libc.flex";
fn libc_pause(a,b,c,d,e,f,g,h){return 0;}
fn la_worker(a,b,c,d,e,f,g,h){return 0;}
fn main(){
 if esp_sdk_heap_init(0x3fcb8000,32768){return 1;}let initial=esp_sdk_heap_free();let hold=esp_sdk_malloc(initial-64);if !hold{return 2;}let low=esp_sdk_heap_free();
 if esp_libc_reent_init()!=-12||esp_libc_main_reent||_impure_ptr||_global_impure_ptr||esp_sdk_heap_free()!=low{return 3;}esp_sdk_free(hold);
 if esp_sdk_heap_free()!=initial||esp_libc_reent_init()||esp_sdk_task_init(){return 4;}esp32_callback32(libc_pause);esp_sdk_task_unmask();let before=esp_sdk_heap_free();let reserve=64;
 while reserve<6100{
  hold=esp_sdk_malloc(before-reserve);if !hold{return 5;}low=esp_sdk_heap_free();let task=esp_sdk_task_create(esp32_callback32(la_worker),0,4096,0);
  if reserve==4928&&task{return 6;}if task{if !load64(task+320)||esp_sdk_task_delete(task)||esp_sdk_task_reap(task){return 7;}}
  if esp_sdk_heap_free()!=low{return 8;}esp_sdk_free(hold);if esp_sdk_heap_free()!=before{return 9;}
  if reserve<4480{reserve=reserve+1472;}else{reserve=reserve+64;}
 }
 return 0;
}
