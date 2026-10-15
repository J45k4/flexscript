import "../../lib/platform/esp32s3-flash.flex";
fn main() {
    esp_uart_write("START: SPI NOR storage\n");let data=alloc(512);let error=esp_flash_region(1048576,8192,1000000);if error {esp_uart_write("INIT ");esp_uart_hex(error);return 1;}
    if esp_flash_region(0,4096,1000000)!= -22 || esp_flash_erase(1,4096,1000000)!= -22 || esp_flash_read(8192,data,1,1000000)!= -22 {return 2;}
    error=esp_flash_erase(0,4096,1000000);if error!=4096 {esp_uart_write("ERASE ");esp_uart_hex(error);return 3;}
    if esp_memory_command(0,3,0,3,0,data,16,1000000) || load8(data)!=233 {return 9;}
    if esp_flash_read(0,data,512,1000000)!=512 {return 4;}let i=0;while i<512 {if load8(data+i)!=255 {return 5;}store8(data+i,i);i=i+1;}
    error=esp_flash_program(239,data,512,1000000);if error!=512 {esp_uart_write("WRITE ");esp_uart_hex(error);return 6;}
    if esp_flash_read(239,data,512,1000000)!=512 {return 7;}i=0;while i<512 {if load8(data+i)!=(i&255) {esp_uart_hex(i);esp_uart_hex(load8(data+i));return 8;}i=i+1;}
    if esp_memory_command(0,3,0,3,0,data,16,1000000) || load8(data)!=233 {return 10;}
    esp_uart_write("PASS: SPI NOR erase, unaligned page-boundary program and readback\n");esp_uart_flush();return 0;
}
