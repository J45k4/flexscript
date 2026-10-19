fn sh_worker(a,b,c,d,e,f,g,h){return 0;}
fn sh_invalid(pointer){let before=esp_sdk_heap_free();if esp_sdk_task_delete(pointer)!=-22||esp_sdk_task_reap(pointer)!=-22||esp_sdk_heap_free()!=before{return 1;}return 0;}
fn sh_run(base){
 if sh_invalid(1)||sh_invalid(0x70000000)||sh_invalid(1<<32){return 1;}
 if esp_sdk_heap_init(base,32768)||sh_runtime_init()||esp_sdk_task_init(){return 2;}esp_sdk_task_unmask();let before=esp_sdk_heap_free();
 let a=esp_sdk_task_create(esp32_callback32(sh_worker),0,4096,0);let b=esp_sdk_task_create(esp32_callback32(sh_worker),0,4096,0);if !a||!b{return 3;}let next=load64(esp_sdk_current+536);
 if sh_invalid(1)||sh_invalid(0x70000000)||sh_invalid((1<<32)+a)||sh_invalid(a+1)||sh_invalid(esp32_state())||sh_invalid(alloc(16)){return 4;}
 if load64(esp_sdk_current+536)!=next||load64(a+544)!=1||load64(b+544)!=1||esp_sdk_task_reap(a)!=-22{return 5;}
 if esp_sdk_task_delete(a)||esp_sdk_task_reap(a)||sh_invalid(a)||load64(b+544)!=1{return 6;}
 if esp_sdk_task_delete(b)||esp_sdk_task_reap(b)||esp_sdk_heap_free()!=before{return 7;}return 0;
}
