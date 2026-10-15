import "esp32s3-memory-spi.flex";
// Quad-capable SPI PSRAM in single-wire command mode, explicit PIO access.
// Requires board-confirmed quad PSRAM and CS1 pad; NOT octal/OPI PSRAM.
// No cache/MMU mapping: this is not an allocator or a normal memory pointer.
global esp_psram_size=0;
global esp_psram_scratch=0;
fn esp_psram_init_quad(cs_pin,cycles) {
    if !esp_gpio_valid(cs_pin) || cycles<1 || cycles>2147483647 {return -22;}
    esp_psram_size=0;if !esp_psram_scratch {esp_psram_scratch=alloc(8);if esp_psram_scratch<0 {return -12;}}
    esp_gpio_route_output(cs_pin,6);
    let error=esp_memory_command(1,0x66,0,0,0,0,0,cycles);if error {return error;}
    error=esp_memory_command(1,0x99,0,0,0,0,0,cycles);if error {return error;}esp_delay_cycles(4000);
    error=esp_memory_command(1,0x9f,0,3,0,esp_psram_scratch,3,cycles);if error {return error;}
    if load8(esp_psram_scratch+1)!=0x5d {return -19;}let density=(load8(esp_psram_scratch+2)>>5)&7;if density>2 {return -19;}
    esp_psram_size=2097152<<density;return esp_psram_size;
}
fn esp_psram_transfer(offset,buffer,size,write,cycles) {
    if !esp_psram_size || offset<0 || size<0 || offset>esp_psram_size || size>esp_psram_size-offset || !esp_buffer_valid(buffer,size) || write<0 || write>1 || cycles<1 || cycles>2147483647 {return -22;}
    let i=0;while i<size {let count=size-i;if count>64 {count=64;}if count>1024-((offset+i)&1023) {count=1024-((offset+i)&1023);}
        let tx=0;let rx=buffer+i;let cmd=3;if write {cmd=2;tx=rx;rx=0;}
        let error=esp_memory_command(1,cmd,offset+i,3,tx,rx,count,cycles);if error {return error;}i=i+count;
    }return size;
}
