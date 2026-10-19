import "../../lib/platform/esp32c3-libc-stdio.flex";
fn main(){
 if esp_libc_stdio_init()!=-19||esp_sdk_heap_init(0x3fcb8000,32768){return 1;}let initial=esp_sdk_heap_free();let reserve=32;
 while reserve<=336{let hold=esp_sdk_malloc(initial-reserve);if !hold{return 2;}let low=esp_sdk_heap_free();let cursor=esp32_load32(esp32_state());
  if esp_libc_stdio_init()!=-12||esp_sdk_heap_free()!=low||esp32_load32(esp32_state())!=cursor||esp_libc_main_reent||esp_libc_static_locks||esp_libc_boot_locks||esp_libc_stdio_ready{return 3;}esp_sdk_free(hold);if esp_sdk_heap_free()!=initial{return 4;}reserve=reserve+16;
 }
 if esp_libc_stdio_init()||!esp_libc_stdio_ready||esp_libc_boot_locks||esp_libc_boot_used!=3{return 5;}let before=esp_sdk_heap_free();if esp_libc_stdio_init()!=-16||esp_sdk_heap_free()!=before{return 6;}return 0;
}
