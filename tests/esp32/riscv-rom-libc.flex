import "../../lib/platform/esp32c3-libc-rom.flex";
fn rom_pause(a,b,c,d,e,f,g,h){return esp_sdk_yield();}
fn rc_call(function){return esp32_call32(function,0,0,0,0,0,0,0,0);}
fn rc_join(task){while load64(task+544)!=2{esp_sdk_yield();}return esp_sdk_task_reap(task);}
fn main(){
 if esp_libc_rom_init()!=-19||esp_sdk_heap_init(0x3fcb8000,32768)||esp_libc_stdio_init()||esp_libc_rom_init()||esp_libc_rom_init()!=-16{return 1;}esp32_callback32(rom_pause);
 if rc_call(esp32_external("rom_table_check"))||rc_call(esp32_external("rom_stat_check")){return 2;}
 // ROM stdio may lazily allocate the shared stdout buffer on first output.
 // Establish that platform-lifetime allocation before checking task reclamation.
 if esp32_call32(esp32_external("rom_printf"),"",0,0,0,0,0,0,0){return 10;}
 if esp_sdk_task_init(){return 3;}esp_sdk_task_unmask();if rc_call(esp32_external("rom_common_check")){return 4;}let before=esp_sdk_heap_free();let round=0;
 while round<3{let a=esp_sdk_task_create(esp32_external("rom_worker"),1,8192,0);let b=esp_sdk_task_create(esp32_external("rom_worker"),2,8192,0);if !a||!b{return 5;}rc_join(a);rc_join(b);if esp_sdk_heap_free()!=before{return 6;}round=round+1;}
 if rc_call(esp32_external("rom_result"))!=6{return 7;}return 0;
}
