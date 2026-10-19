import "../../lib/platform/esp32c3-libc.flex";
global lr_error=0;
fn libc_pause(a,b,c,d,e,f,g,h){return esp_sdk_yield();}
fn lr_call(name,arg){return esp32_call32(name,arg,0,0,0,0,0,0,0);}
fn lr_worker(a,b,c,d,e,f,g,h){return esp32_call32(esp32_external("libc_worker"),a,8,0,0,0,0,0,0);}
fn lr_join(task){while load64(task+544)!=2 {esp_sdk_yield();}return esp_sdk_task_reap(task);}
fn main(){
 if esp_libc_reent_init()!=-19||esp_sdk_heap_init(0x3fcb8000,32768)||esp_libc_reent_init()||esp_libc_reent_init()!=-16{return 1;}esp32_callback32(libc_pause);
 let identity=esp_libc_getreent();if lr_call(esp32_external("libc_identity"),0)!=identity||_impure_ptr!=identity||_global_impure_ptr!=identity{return 2;}
 if lr_call(esp32_external("libc_memory"),0)||esp_sdk_task_init(){return 3;}esp_sdk_task_unmask();let before=esp_sdk_heap_free();esp_libc_errno(identity,444);
 let round=0;while round<6{
  let a=esp_sdk_task_create(esp32_callback32(lr_worker),1,4096,0);let b=esp_sdk_task_create(esp32_callback32(lr_worker),2,4096,0);if !a||!b||!load64(a+320)||load64(a+320)==load64(b+320){return 4;}
  lr_join(a);lr_join(b);if _impure_ptr!=identity||esp_libc_getreent()!=identity||esp32_load32(identity)!=444||esp_sdk_heap_free()!=before{return 5;}round=round+1;
 }
 if lr_call(esp32_external("libc_status"),0)!=12{return 6;}return 0;
}
