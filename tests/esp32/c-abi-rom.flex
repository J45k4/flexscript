import "../../lib/platform/esp32.flex";
fn main() {
    esp_uart_write("START: C ABI ROM\r\n");let text="native Flexscript";
    let n=esp32_call32(0x400014c0,text,0,0,0,0,0,0,0);if n!=17 {esp_uart_hex(n);return 1;}
    let q=esp32_call64(0x4000cff8,0x9abcdef0,0x12345678,1023,0,0,0,0,0);
    if q!=1282276116777898 {esp_uart_hex(q);return 2;}
    esp_uart_write("PASS: windowed ROM strlen and 64-bit division\r\n");esp_uart_flush();return 0;
}
