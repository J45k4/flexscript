import "../../lib/platform/esp32s3-psram.flex";
fn main() {
    esp_uart_write("START: quad PSRAM PIO\n");let size=esp_psram_init_quad(26,1000000);if size!=8388608 {esp_uart_hex(size);return 1;}
    let data=alloc(130);let i=0;while i<130 {store8(data+i,i^0x5a);i=i+1;}
    if esp_psram_transfer(1007,data,130,1,1000000)!=130 {return 2;}
    i=0;while i<130 {store8(data+i,0);i=i+1;}
    if esp_psram_transfer(1007,data,130,0,1000000)!=130 {return 3;}
    i=0;while i<130 {if load8(data+i)!=(i^0x5a) {esp_uart_hex(i);esp_uart_hex(load8(data+i));return 4;}i=i+1;}
    if esp_psram_transfer(size,data,1,0,1000)!= -22 {return 5;}
    esp_uart_write("PASS: quad PSRAM ID, burst-boundary writes and readback\n");esp_uart_flush();return 0;
}
