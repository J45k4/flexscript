import "../../lib/platform/esp32c3-libc-rom.flex";
fn main(){if esp_sdk_heap_init(0x3fcb8000,32768)||esp_libc_stdio_init()||esp_libc_rom_init(){return 1;}return esp32_call32(esp32_external("rom_peer"),0,0,0,0,0,0,0,0);}
