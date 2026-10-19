import "../../lib/platform/esp32c3-libc-stdio.flex";
fn stdio_pause(a,b,c,d,e,f,g,h){return 0;}
fn main(){if esp_sdk_heap_init(0x3fcb8000,32768)||esp_libc_stdio_init(){return 1;}esp_libc_posix_bind();esp32_callback32(stdio_pause);return esp32_call32(esp32_external("stdio_peer"),0,0,0,0,0,0,0,0);}
