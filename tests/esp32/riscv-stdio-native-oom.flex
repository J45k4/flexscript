import "../../lib/platform/esp32c3-libc-stdio.flex";
fn main(){
 if esp_sdk_heap_init(0x3fcb8000,32768)||alloc(32768)<0{return 1;}let before=esp_sdk_heap_free();let cursor=esp32_load32(esp32_state());
 if esp_libc_stdio_init()!=-12||esp_sdk_heap_free()!=before||esp32_load32(esp32_state())!=cursor||esp_libc_main_reent||esp_libc_static_locks||esp_libc_stdio_ready{return 2;}return 0;
}
