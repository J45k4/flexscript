import "../../lib/platform/esp32c3-libc-locks.flex";
global lc_stage=0;global lc_error=0;global lc_index=0;global lc_worker=0;global lc_medium=0;
fn lc_call(op,index){return esp32_call32(esp32_external("libc_lock_call"),op,index,0,0,0,0,0,0);}
fn libc_probe(a,b,c,d,e,f,g,h){if a==1{if lc_stage!=1{lc_error=1;}lc_stage=2;}else{if lc_stage!=3{lc_error=2;}lc_stage=4;}return 0;}
fn lc_thread(a,b,c,d,e,f,g,h){let result=esp32_call32(esp32_external("libc_lock_worker"),lc_index,0,0,0,0,0,0,0);if result{lc_error=10+result;}return 0;}
fn lc_middle(a,b,c,d,e,f,g,h){if lc_stage!=4{lc_error=3;}lc_stage=5;return 0;}
fn lc_join(task){while load64(task+544)!=2{esp_sdk_yield();}return esp_sdk_task_reap(task);}
fn main(){
 esp_libc_locks_bind();esp32_callback32(libc_probe);if esp_sdk_heap_init(0x3fcb8000,32768){return 1;}let before=esp_sdk_heap_free();
 // Legacy zero/static initializers are no-ops before scheduler startup.
 if lc_call(1,0)||lc_call(1,1)||lc_call(5,0)||lc_call(5,1)||esp_sdk_heap_free()!=before{return 2;}lc_call(2,0);lc_call(3,0);lc_call(4,0);
 let i=0;while i<4{lc_call(8,i);lc_call(0,i);let handle=lc_call(5,i);if !handle||!lc_call(6,i){return 3;}lc_call(2,i);if lc_call(1,i)||load64(handle)||load64(handle+8){return 4;}lc_call(3,i);lc_call(4,i);if i<2{if lc_call(5,i){return 5;}}else{if lc_call(5,i)!=handle{return 6;}lc_call(7,i);}lc_call(4,i);i=i+1;}
 if esp_sdk_heap_free()!=before||esp_sdk_task_init(){return 7;}esp_sdk_task_unmask();before=esp_sdk_heap_free();
 // Each ABI/type crosses a C stack frame while blocked, donates priority to
 // main, then wakes ahead of a medium-priority task after the final release.
 i=0;while i<4{lc_index=i;lc_stage=1;lc_error=0;
  if i<2{if lc_call(1,i){return 8;}}else{lc_call(0,i);lc_call(2,i);}let handle=lc_call(5,i);
  if (i&1){lc_call(2,i);if lc_call(1,i){return 9;}lc_call(3,i);if load64(handle+8)!=2{return 10;}}
  else{if lc_call(1,i)!=4294967295||load64(handle+8)!=1{return 11;}}
  lc_worker=esp_sdk_task_create(esp32_callback32(lc_thread),0,4096,9);lc_medium=esp_sdk_task_create(esp32_callback32(lc_middle),0,4096,5);if !lc_worker||!lc_medium{return 12;}
  esp_sdk_yield();if lc_stage!=2||load64(esp_sdk_current+624)!=9||esp_sdk_task_get_priority(0)!=0{return 13;}
  if (i&1){lc_call(3,i);esp_sdk_yield();if lc_stage!=2||load64(esp_sdk_current+624)!=9{return 14;}}
  lc_stage=3;lc_call(3,i);esp_sdk_yield();if lc_stage!=5||load64(esp_sdk_current+624)!=0||lc_error{return 15;}
  lc_join(lc_worker);lc_join(lc_medium);lc_call(4,i);if i>=2{lc_call(7,i);}if !lc_call(6,i)||esp_sdk_heap_free()!=before{return 16;}i=i+1;
 }
 // Failed nonblocking attempts preserve an existing interrupt mask.
 lc_call(0,0);let ps=esp32_irq_save();if lc_call(1,0)||lc_call(1,0)!=4294967295{return 17;}let masked=esp32_irq_save();if masked&8{return 18;}lc_call(3,0);esp32_irq_restore(ps);lc_call(4,0);
 if esp_sdk_heap_free()!=before{return 19;}return 0;
}
