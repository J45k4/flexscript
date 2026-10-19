import "../../lib/platform/esp32s3-xip.flex";
import "../../lib/platform/esp32s3.flex";
fn sx_inner(n) {if n<1 {return 7;}return sx_inner(n-1)+n;}
fn sx_callback(n) {return sx_inner(n)+3;}
fn main() {let callback=esp32_callback(sx_callback);if callback<0x42000000 || callback>=0x42300000 {return 2;}let result=esp32_call(callback,9);if result!=55 {return 1;}esp_uart_write("PASS: S3 cached native calls, recursion and private callback\r\n");esp_uart_flush();return 0;}
