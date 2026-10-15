import "../../lib/platform/esp32s3-sd.flex";
fn main() {
    esp_uart_write("START: SD card\n");let error=esp_sd_init(4,5,6,20000000);if error {esp_uart_write("INIT ");esp_uart_hex(error);return 1;}
    esp_uart_write("CAPACITY ");esp_uart_hex(esp_sd_blocks);let data=alloc(512);
    error=esp_sd_block(8,data,0,20000000);if error!=512 {esp_uart_write("READ ");esp_uart_hex(error);return 2;}
    let i=0;while i<512 {if load8(data+i)!=(i&255) {esp_uart_write("DATA ");esp_uart_hex(i);esp_uart_hex(load8(data+i));return 3;}i=i+1;}
    i=0;while i<512 {store8(data+i,255-(i&255));i=i+1;}
    error=esp_sd_block(9,data,1,20000000);if error!=512 {esp_uart_write("WRITE ");esp_uart_hex(error);return 4;}
    i=0;while i<512 {store8(data+i,0);i=i+1;}
    if esp_sd_block(9,data,0,20000000)!=512 {return 5;}
    i=0;while i<512 {if load8(data+i)!=255-(i&255) {return 6;}i=i+1;}
    if esp_sd_block(esp_sd_blocks,data,0,1000)!= -22 {return 7;}
    esp_uart_write("PASS: SD card initialization, capacity, block read and write/readback\n");esp_uart_flush();return 0;
}
