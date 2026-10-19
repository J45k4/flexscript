import "../../lib/platform/esp32c3-sdk-sync.flex";
global tls_stage=0;global tls_error=0;global tls_tp_main=0;global tls_tp_one=0;global tls_tp_two=0;
fn tls_call(function,value){return esp32_call32(function,value,0,0,0,0,0,0,0);}
fn esp_platform_init(){return tls_call(esp32_external("tls_validate_initial"),0);}
fn tls_worker(a,b,c,d,e,f,g,h){
 let tp=tls_call(esp32_external("tls_address"),0);if !tp||tp==tls_tp_main||tls_call(esp32_external("tls_validate_initial"),0){tls_error=1;return 0;}
 if a==17{tls_tp_one=tp;}else{tls_tp_two=tp;}tls_call(esp32_external("tls_set"),a);if tls_call(esp32_external("tls_stack_probe"),0){tls_error=2;}
 let i=0;while i<3{if tls_call(esp32_external("tls_validate_set"),a){tls_error=3;}tls_stage=tls_stage+1;esp_sdk_yield();i=i+1;}return 0;
}
fn main(){
 tls_tp_main=tls_call(esp32_external("tls_address"),0);if !tls_tp_main||esp_platform_init(){return 1;}tls_call(esp32_external("tls_set"),99);
 if esp_sdk_heap_init(0x3fcb8000,32768)||esp_sdk_task_init(){return 2;}esp_sdk_task_unmask();let before=esp_sdk_heap_free();esp32_store32(esp32_state()+48,1);if esp_sdk_task_create(esp32_callback32(tls_worker),17,4096,0)||esp_sdk_heap_free()!=before{return 14;}esp32_store32(esp32_state()+48,0);let round=0;
 while round<6{tls_stage=0;tls_tp_one=0;tls_tp_two=0;let one=esp_sdk_task_create(esp32_callback32(tls_worker),17,4096,0);let two=esp_sdk_task_create(esp32_callback32(tls_worker),29,4096,0);if !one||!two{return 3;}
  while load64(one+544)!=2||load64(two+544)!=2{if tls_call(esp32_external("tls_validate_set"),99){return 4;}esp_sdk_yield();}
  if tls_error||tls_stage!=6||!tls_tp_one||!tls_tp_two||tls_tp_one==tls_tp_two{return 5+tls_error;}
  if esp_sdk_task_reap(one)||esp_sdk_task_reap(two)||esp_sdk_heap_free()!=before{return 9;}round=round+1;
 }
 let reserve=16;while reserve<=1040{let hold=esp_sdk_malloc(esp_sdk_heap_free()-reserve);if !hold{return 10;}let low=esp_sdk_heap_free();if esp_sdk_task_create(esp32_callback32(tls_worker),17,4096,0)||esp_sdk_heap_free()!=low{return 11;}esp_sdk_free(hold);if esp_sdk_heap_free()!=before{return 12;}reserve=reserve+1024;}
 if tls_call(esp32_external("tls_validate_set"),99){return 13;}return 0;
}
