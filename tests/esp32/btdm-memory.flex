import "../../lib/platform/esp32-xip.flex";
import "../../lib/platform/esp32-bluetooth.flex";
fn main() {
    if esp32_state()!=0x3ffc0000 {return 1;}
    let native=alloc(1024);if native!=0x3ffb6400 {return 2;}store64(native,0x123456789abcdef);
    esp32_store32(0x3ffb1000,0xdeadbeef);esp32_store32(0x3ffb8000,0xdeadbeef);
    if esp_bt_rom_memory() || load64(native)!=0x123456789abcdef || esp32_load32(0x3ffb1000) || esp32_load32(0x3ffb8000) {return 3;}
    if esp_sdk_heap_init(0x3ffc8000,98304) || esp_sdk_task_init() || esp_sdk_timer_init() {return 4;}
    esp_sdk_delay(2);if load64(native)!=0x123456789abcdef {return 5;}
    let rest=alloc(6144);if rest!=0x3ffb6800 || alloc(8)!= -12 {return 6;}
    esp_uart_write("PASS: Bluetooth ROM reservations, isolated native heap and task state\r\n");return 0;
}
