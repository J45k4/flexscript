import "../../lib/platform/esp32c3-libc-rom.flex";
fn main(){
 if esp_sdk_heap_init(0x3fcb8000,32768)||esp_libc_stdio_init()||esp_sdk_task_init(){return 1;}let before=esp_sdk_heap_free();
 if esp_libc_rom_init()!=-16||esp_sdk_heap_free()!=before||esp_libc_rom_table||esp32_load32(esp_libc_rom_syscall_slot())||esp32_load32(esp_libc_rom_global_slot()){return 2;}return 0;
}
