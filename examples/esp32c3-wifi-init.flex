import "../lib/platform/esp32c3-wifi.flex";
fn main(){
 esp_uart_write("C3 WIFI: runtime initialization\r\n");let arena=esp_sdk_heap_min();if esp_sdk_heap_init(arena,esp_sdk_heap_max()-arena)||esp_libc_stdio_init()||esp_libc_rom_init()||esp_sdk_task_init(){return 1;}esp_radio_log=1;esp_sdk_task_unmask();
 esp_uart_write("C3 WIFI: entering actual vendor initialization\r\n");let r=esp_wifi_station_init();esp_uart_write("C3 WIFI: initializer returned ");esp_uart_hex(r);esp_uart_write(" cleanup ");esp_uart_hex(esp_wifi_cleanup_error);esp_uart_write("\r\n");return r;
}
