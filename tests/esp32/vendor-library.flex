import "../../lib/platform/esp32.flex";
fn main() {
    esp_uart_write("START: vendor WPA archive\r\n");let bytes=alloc(8);let decode=esp32_external("hexstr2bin");
    let status=esp32_call32(decode,"deadbeef01234567",bytes,8,0,0,0,0,0);if status {esp_uart_hex(status);return 1;}
    if load64(bytes)!=0x67452301efbeadde {esp_uart_hex(load64(bytes));return 2;}
    if esp32_call32(decode,"zz",bytes,1,0,0,0,0,0)!=0xffffffff {return 3;}
    esp_uart_write("PASS: linked vendor WPA archive, valid and invalid hex decoding\r\n");esp_uart_flush();return 0;
}
