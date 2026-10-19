import "../../lib/platform/esp32c3-libc-locks.flex";
import "../../lib/platform/esp32c3-irq.flex";
import "../../lib/platform/esp32c3-sdk-preempt.flex";
global lp_error=0;global lp_done=0;
fn lp_call(op,index){return esp32_call32(esp32_external("libc_lock_call"),op,index,0,0,0,0,0,0);}
fn libc_probe(a,b,c,d,e,f,g,h){let start=esp32_cycles();while ((esp32_cycles()-start)&4294967295)<320000{}return 0;}
fn lp_worker(a,b,c,d,e,f,g,h){let result=esp32_call32(esp32_external("libc_lock_stress"),a,12,0,0,0,0,0,0);if result{lp_error=result;}lp_done=lp_done+1;return 0;}
fn main(){
 esp_libc_locks_bind();esp32_callback32(libc_probe);esp_irq_enable();if esp_sdk_heap_init(0x3fcb8000,32768)||esp_sdk_task_init(){return 1;}let before=esp_sdk_heap_free();lp_call(0,1);lp_call(0,3);
 let a=esp_sdk_task_create(esp32_callback32(lp_worker),1,4096,0);let b=esp_sdk_task_create(esp32_callback32(lp_worker),1,4096,0);if !a||!b||esp_sdk_preempt_start(1000){return 2;}
 let start=esp32_cycles();while lp_done!=2{if ((esp32_cycles()-start)&4294967295)>400000000{return 3;}}
 while load64(a+544)!=2||load64(b+544)!=2{esp_sdk_yield();}esp_sdk_task_reap(a);esp_sdk_task_reap(b);
 a=esp_sdk_task_create(esp32_callback32(lp_worker),3,4096,0);b=esp_sdk_task_create(esp32_callback32(lp_worker),3,4096,0);if !a||!b{return 4;}
 while lp_done!=4{if ((esp32_cycles()-start)&4294967295)>800000000{return 5;}}
 while load64(a+544)!=2||load64(b+544)!=2{esp_sdk_yield();}if esp_sdk_preempt_stop()||esp_sdk_preempt_switches<8{return 6;}esp_sdk_task_reap(a);esp_sdk_task_reap(b);
 let count=esp32_call32(esp32_external("libc_lock_count"),0,0,0,0,0,0,0,0);if count!=48||lp_error{return 7;}lp_call(4,1);lp_call(4,3);if esp_sdk_heap_free()!=before{return 8;}return 0;
}
