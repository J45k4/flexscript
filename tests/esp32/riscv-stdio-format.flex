import "../../lib/platform/esp32c3-libc-stdio.flex";
fn main(){if esp_sdk_heap_init(0x3fcb8000,32768)||esp_libc_stdio_init(){return 1;}return esp32_call32(esp32_external("stdio_smoke"),0,0,0,0,0,0,0,0);}
