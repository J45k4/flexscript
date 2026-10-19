import "../../lib/platform/esp32-sdk-heap.flex";
global dm_available=0;
fn dm_allocate(n) {return esp_sdk_malloc(n);}
fn dm_release(p) {return esp_sdk_free(p);}
fn dm_arena_clean() {return !esp_sdk_allocated && esp_sdk_heap_free()==dm_available;}
fn main() {let base=esp_sdk_heap_min();let size=esp_sdk_heap_max()-base;let r=esp_sdk_heap_init(base,size);if r {return r;}dm_available=esp_sdk_heap_free();r=dm_run();if r {esp_uart_write("SMP DURABLE MAX FAIL ");esp_uart_hex(r);}else {esp_uart_write("PASS: SMP durable-max ");}esp_uart_hex(dm_checks);esp_uart_write("\r\n");esp_uart_flush();return r;}
