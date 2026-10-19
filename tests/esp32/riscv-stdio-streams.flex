import "../../lib/platform/esp32c3-libc-stdio.flex";
fn stdio_pause(a,b,c,d,e,f,g,h){return esp_sdk_yield();}
fn ss_call(function,arg){return esp32_call32(function,arg,0,0,0,0,0,0,0);}
fn ss_join(task){while load64(task+544)!=2{esp_sdk_yield();}return esp_sdk_task_reap(task);}
fn main(){
 if esp_sdk_heap_init(0x3fcb8000,32768)||esp_libc_stdio_init()||esp_sdk_task_init(){return 1;}esp_libc_posix_bind();esp32_callback32(stdio_pause);esp_sdk_task_unmask();
 if ss_call(esp32_external("stdio_prepare"),0)||ss_call(esp32_external("stdio_static_locks"),0){return 2;}let before=esp_sdk_heap_free();let round=0;
 while round<3{
  let a=esp_sdk_task_create(esp32_external("stdio_worker"),1,8192,0);let b=esp_sdk_task_create(esp32_external("stdio_worker"),2,8192,0);if !a||!b{return 3;}ss_join(a);ss_join(b);
  if ss_call(esp32_external("stdio_check"),0)||esp_sdk_heap_free()!=before{return 4;}round=round+1;
 }
 let task=esp_sdk_task_create(esp32_external("stdio_redirect_global"),0,4096,0);if !task{return 5;}ss_join(task);
 let check=ss_call(esp32_external("stdio_check"),1);if check{return 600+check;}check=ss_call(esp32_external("stdio_errors"),0);if check{return 700+check;}if esp_sdk_heap_free()!=before{return 800;}return 0;
}
