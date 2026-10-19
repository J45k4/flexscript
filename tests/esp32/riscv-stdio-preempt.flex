import "../../lib/platform/esp32c3-libc-stdio.flex";
import "../../lib/platform/esp32c3-sdk-preempt.flex";
fn stdio_pause(a,b,c,d,e,f,g,h){let start=esp32_cycles();while ((esp32_cycles()-start)&4294967295)<320000{}return 0;}
fn ss_call(function,arg){return esp32_call32(function,arg,0,0,0,0,0,0,0);}
fn ss_join(task){while load64(task+544)!=2{esp_sdk_yield();}return esp_sdk_task_reap(task);}
fn main(){
 if esp_sdk_heap_init(0x3fcb8000,32768)||esp_libc_stdio_init()||esp_sdk_task_init(){return 1;}esp_libc_file_locks_bind();esp32_callback32(stdio_pause);esp_irq_enable();if esp_sdk_preempt_start(1000){return 7;}
 if ss_call(esp32_external("stdio_prepare"),0){return 2;}let before=esp_sdk_heap_free();let round=0;
 while round<3{
  let a=esp_sdk_task_create(esp32_external("stdio_worker"),1,8192,0);let b=esp_sdk_task_create(esp32_external("stdio_worker"),2,8192,0);if !a||!b{return 3;}ss_join(a);ss_join(b);
  if ss_call(esp32_external("stdio_check"),0)||esp_sdk_heap_free()!=before{return 4;}round=round+1;
 }
 let check=ss_call(esp32_external("stdio_check"),1);if check{return 600+check;}if esp_sdk_heap_free()!=before{return 800;}if esp_sdk_preempt_stop()||esp_sdk_preempt_switches<8{return 8;}return 0;
}
