import "../lib/platform/esp32c3.flex";
fn main() {esp_uart_write("Hello from native Flexscript on ESP32-C3\r\n");esp_uart_hex(0x8877665544332211);esp_uart_write("\r\n");esp_uart_flush();return 0;}
