import "../../lib/platform/esp32.flex";
import "../../lib/platform/esp32-xip.flex";
fn main() {
    esp_uart_write("START: executable flash\r\n");
    if esp_xip_enable() {return 1;}
    if esp32_call32(esp32_external("xip_probe"),123,0,0,0,0,0,0,0)!=0x123456f3 {return 2;}
    esp_uart_write("PASS: cached flash instructions and constants\r\n");esp_uart_flush();return 0;
}
