import "../../lib/platform/esp32-flash.flex";
import "../../lib/platform/esp32.flex";
fn flash_literal(n) {return esp32_external("test_flash_source");}
fn fo_run() {
    let data=alloc(1024);if data<=0 {return 1;}let cycles=80000000;let result=esp_flash_region(0x3e0000,8192,cycles);esp_uart_write("FLASH init ");esp_uart_hex(result);esp_uart_write(" jedec ");esp_uart_hex(esp_flash_jedec);esp_uart_write(" protected ");esp_uart_hex(esp_flash_protected_end());esp_uart_write("\r\n");if result {return 2;}
    let critical=esp32_callback(ef_critical);if critical<0x40080000 || critical>=0x400a0000 || esp32_callback(ef_controller)<0x40080000 || esp32_callback(ef_controller)>=0x400a0000 || esp32_callback(flash_literal)<0x400d0000 || flash_literal(0)<0x3f400000 || flash_literal(0)>=0x3f800000 {return 3;}
    if esp_flash_region(0,4096,cycles)!= -22 || esp_flash_region(esp_flash_protected_end()-4096,4096,cycles)!= -22 || esp_flash_region(0x400000,4096,cycles)!= -22 || esp_flash_erase(1,4096,cycles)!= -22 || esp_flash_read(8192,data,1,cycles)!= -22 || esp_flash_program(0,data,1,0)!= -22 {return 4;}
    esp_uart_write("FLASH bounds okay\r\n");if esp_flash_write_access(1,cycles) {return 14;}let erased=esp_flash_erase(0,8192,cycles);esp_uart_write("FLASH erase ");esp_uart_hex(erased);esp_uart_write("\r\n");if erased!=8192 || esp_flash_read(0,data,1024,cycles)!=1024 {return 5;}let i=0;while i<1024 {if load8(data+i)!=255 {return 6;}store8(data+i,(i*37+11)&255);i=i+1;}
    let written=esp_flash_program(239,data,513,cycles);esp_uart_write("FLASH program ");esp_uart_hex(written);esp_uart_write("\r\n");if written!=513 {esp_uart_write("FLASH TX/RX ");let z=0;while z<17 {esp_uart_hex(load8(esp_flash_scratch+128+z));esp_uart_hex(load8(esp_flash_scratch+192+z));z=z+1;}esp_uart_write("\r\n");return 7;}i=0;while i<1024 {store8(data+i,0);i=i+1;}if esp_flash_read(238,data,515,cycles)!=515 || load8(data)!=255 || load8(data+514)!=255 {return 8;}i=0;while i<513 {if load8(data+1+i)!=((i*37+11)&255) {return 9;}i=i+1;}
    // The final illegal transition must prevent earlier legal bytes changing.
    i=0;while i<65 {store8(data+i,0);i=i+1;}store8(data+64,255);if esp_flash_program(239,data,65,cycles)!= -30 || esp_flash_read(239,data,65,cycles)!=65 || load8(data)!=11 {return 10;}
    if esp_flash_program(4093,flash_literal(0),28,cycles)!=28 || esp_flash_read(4093,data,28,cycles)!=28 {return 11;}i=0;while i<28 {if load8(data+i)!=load8(flash_literal(0)+i) {return 12;}i=i+1;}
    if esp_flash_read(8192,data,0,cycles) || esp_flash_program(8192,data,0,cycles) || esp_flash_read(0,esp_flash_scratch,1,cycles)!= -22 {return 13;}
    if esp_flash_erase(0,8192,cycles)!=8192 || esp_flash_read(0,data,1024,cycles)!=1024 {return 15;}i=0;while i<1024 {if load8(data+i)!=255 {return 16;}i=i+1;}if esp_flash_read(4093,data,28,cycles)!=28 {return 17;}i=0;while i<28 {if load8(data+i)!=255 {return 18;}i=i+1;}
    esp_uart_write("PASS: cached original ESP32 flash, page/sector crossing, preflight and firmware bounds\r\n");esp_uart_flush();return 0;
}
