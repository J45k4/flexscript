import "../../lib/platform/esp32c3-sdk-sync.flex";
global trace=0;global used=0;global failure=0;global mutex=0;global high=0;global middle=0;
fn record(value){store64(trace+used*8,value);used=used+1;return 0;}
fn join(task){while load64(task+544)!=2 {esp_sdk_yield();}return esp_sdk_task_reap(task);}
fn peer(a,b,c,d,e,f,g,h){let word=0x8877665544332200+a;let i=0;while i<2 {record(a);esp_sdk_yield();if word!=0x8877665544332200+a {failure=1;}i=i+1;}return 0;}
fn highest(a,b,c,d,e,f,g,h){record(15);if !esp_sdk_mutex_lock(mutex){failure=2;}record(30);if !esp_sdk_mutex_unlock(mutex){failure=3;}return 0;}
fn medium(a,b,c,d,e,f,g,h){record(40);return 0;}
fn low(a,b,c,d,e,f,g,h){
 if !esp_sdk_mutex_lock(mutex)||!esp_sdk_mutex_lock(mutex){failure=4;}record(10);
 middle=esp_sdk_task_create(esp32_callback32(medium),0,4096,5);high=esp_sdk_task_create(esp32_callback32(highest),0,4096,9);if !middle||!high{failure=5;return 0;}
 esp_sdk_yield();if load64(esp_sdk_current+624)!=9||esp_sdk_task_get_priority(0)!=1{failure=6;}record(20);
 if !esp_sdk_mutex_unlock(mutex){failure=7;}esp_sdk_yield();if load64(esp_sdk_current+624)!=9{failure=8;}
 if !esp_sdk_mutex_unlock(mutex){failure=9;}esp_sdk_yield();if load64(esp_sdk_current+624)!=1{failure=10;}record(50);return 0;
}
fn main(){
 if esp_sdk_heap_init(0x3fcb8000,32768)||esp_sdk_task_init(){return 1;}esp_sdk_task_unmask();trace=alloc(1024);let baseline=esp_sdk_heap_free();
 if esp_sdk_task_get_priority(0)!=0||esp_sdk_task_set_priority(0,25)!=-22||esp_sdk_task_get_priority(0x1234)!=-22{return 2;}
 let a=esp_sdk_task_create(esp32_callback32(peer),3,4096,3);let b=esp_sdk_task_create(esp32_callback32(peer),9,4096,9);let c=esp_sdk_task_create(esp32_callback32(peer),5,4096,5);if !a||!b||!c{return 3;}
 join(a);join(b);join(c);let wanted=0x030305050909;let i=0;while i<6 {if load64(trace+i*8)!=((wanted>>(i*8))&255){return 4;}i=i+1;}if used!=6||esp_sdk_heap_free()!=baseline{return 5;}
 used=0;a=esp_sdk_task_create(esp32_callback32(peer),11,4096,7);b=esp_sdk_task_create(esp32_callback32(peer),22,4096,7);c=esp_sdk_task_create(esp32_callback32(peer),33,4096,7);if !a||!b||!c{return 6;}join(a);join(b);join(c);
 wanted=0x0b16210b1621;i=0;while i<6 {if load64(trace+i*8)!=((wanted>>(i*8))&255){return 7;}i=i+1;}if used!=6||esp_sdk_heap_free()!=baseline{return 8;}
 used=0;mutex=esp_sdk_mutex_create(1);a=esp_sdk_task_create(esp32_callback32(low),0,4096,1);if !mutex||!a{return 9;}join(a);join(high);join(middle);esp_sdk_free(mutex);
 if used!=6||load64(trace)!=10||load64(trace+8)!=15||load64(trace+16)!=20||load64(trace+24)!=30||load64(trace+32)!=40||load64(trace+40)!=50{return 10;}
 if failure||esp_sdk_heap_free()!=baseline{return 20+failure;}return 0;
}
