// Original ESP32 XIP firmware. Reserve this8KiB region in your flash layout.
// Never formats unknown/corrupt media; first use requires two erased banks.
import "../lib/platform/esp32-settings.flex";
import "../lib/platform/esp32.flex";
fn main() {
    let size=kv_size(4096);let work=alloc(size);if work<=0 {return 1;}let result=esp_settings_init(0x3e0000,4096,work,size,80000000);
    if result== -61 {result=esp_settings_create();}if result {esp_uart_write("Settings mount error ");esp_uart_hex(result);esp_uart_write("\r\n");return 2;}
    let count=0;result=kv_get("example:boots",13);if !result {if kv_value_type!=4 || kv_value_size!=4 {return 3;}count=kv_u32(kv_value);}else if result!= -2 {return 4;}
    let value=alloc(4);if value<=0 {return 5;}count=(count+1)&4294967295;kv_put32(value,count);
    result=kv_set("example:boots",13,4,value,4);if !result {result=esp_settings_commit();}if result {esp_uart_write("Settings commit error ");esp_uart_hex(result);esp_uart_write("\r\n");return 6;}
    esp_uart_write("Persistent boot count ");esp_uart_hex(count);esp_uart_write("\r\n");esp_uart_flush();return 0;
}
