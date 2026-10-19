import "../../lib/platform/esp32c3-radio-os.flex";
fn main(){
 // Retain real newlib export bridges without initializing them. Supported
 // data bases are aligned; the branch is unreachable on both chip profiles.
 if esp32_state()&1{esp_libc_stdio_init();esp_libc_rom_init();}
 let arena=esp_sdk_heap_min();if esp_sdk_heap_init(arena,esp_sdk_heap_max()-arena)||esp_sdk_task_init(){return 1;}
 esp32_call32(esp32_external("c_rv_osi_reset"),0,0,0,0,0,0,0,0);let before=esp_sdk_heap_free();
 if esp_radio_os_init()!=-19 || esp_radio_owner || esp_radio_osi || esp_sdk_timer_task || esp_sdk_heap_free()!=before{return 2;}
 if esp32_call32(esp32_external("c_rv_osi_guard_check"),1,0,0,0,0,0,0,0){return 3;}return 0;
}
