import "../../lib/platform/esp32c3-libc-rom.flex";
fn main(){
 if esp_sdk_heap_init(0x3fcb8000,32768)||esp_libc_stdio_init(){return 1;}let before=esp_sdk_heap_free();let slot=esp_libc_rom_syscall_slot();let global_slot=esp_libc_rom_global_slot();
 esp32_store32(slot,0x12345678);if esp_libc_rom_init()!=-16||esp32_load32(slot)!=0x12345678||esp32_load32(global_slot)||esp_sdk_heap_free()!=before||esp_libc_rom_table{return 2;}esp32_store32(slot,0);
 esp32_store32(global_slot,0x12345678);if esp_libc_rom_init()!=-16||esp32_load32(global_slot)!=0x12345678||esp32_load32(slot)||esp_sdk_heap_free()!=before||esp_libc_rom_table{return 3;}esp32_store32(global_slot,0);
 esp_sdk_task_unmask();if esp_libc_rom_init()!=-16||esp32_load32(slot)||esp32_load32(global_slot)||esp_sdk_heap_free()!=before{return 4;}let ps=esp32_irq_save();if !(ps&8){return 5;}
 if esp_libc_rom_init(){return 6;}let installed=esp_libc_rom_table;before=esp_sdk_heap_free();if esp_libc_rom_init()!=-16||esp_libc_rom_table!=installed||esp32_load32(slot)!=installed||esp_sdk_heap_free()!=before{return 7;}return 0;
}
