import "esp32s3-memory-spi.flex";
// JEDEC SPI NOR, up to 16 MiB. Explicit bounded storage region; offsets in
// read/program/erase are relative to it. The first MiB is never writable.
// Does not support octal flash, encryption, secure boot, or live cached code.
global esp_flash_start=0;
global esp_flash_size=0;
global esp_flash_scratch=0;
fn esp_flash_region(start,size,cycles) {
    if start<1048576 || (start&4095) || size<4096 || (size&4095) || start>0xffffff || size>16777216-start {return -22;}
    if !esp_flash_scratch {esp_flash_scratch=alloc(8);if esp_flash_scratch<0 {return -12;}}
    let error=esp_memory_command(0,0x9f,0,0,0,esp_flash_scratch,3,cycles);if error {return error;}
    let density=load8(esp_flash_scratch+2);if density<20 || density>24 || load8(esp_flash_scratch)==255 || !load8(esp_flash_scratch) {return -19;}
    if start+size>(1<<density) {return -22;}esp_flash_start=start;esp_flash_size=size;return 0;
}
fn esp_flash_wait(cycles) {
    if !esp_flash_scratch || cycles<1 || cycles>2147483647 {return -22;}
    let start=esp32_cycles();let busy=1;while busy {
        let error=esp_memory_command(0,5,0,0,0,esp_flash_scratch,1,cycles);if error {return error;}
        busy=load8(esp_flash_scratch)&1;if busy && ((esp32_cycles()-start)&4294967295)>=cycles {return -110;}
    }return 0;
}
fn esp_flash_enable(cycles) {
    let error=esp_flash_wait(cycles);if error {return error;}error=esp_memory_command(0,6,0,0,0,0,0,cycles);if error {return error;}
    error=esp_memory_command(0,5,0,0,0,esp_flash_scratch,1,cycles);if error {return error;}if !(load8(esp_flash_scratch)&2) {return -13;}return 0;
}
fn esp_flash_read(offset,buffer,size,cycles) {
    if !esp_flash_size || offset<0 || size<0 || offset>esp_flash_size || size>esp_flash_size-offset || !esp_buffer_valid(buffer,size) {return -22;}
    let error=esp_flash_wait(cycles);if error {return error;}let i=0;while i<size {let count=size-i;if count>64 {count=64;}
        error=esp_memory_command(0,3,esp_flash_start+offset+i,3,0,buffer+i,count,cycles);if error {return error;}i=i+count;
    }return size;
}
fn esp_flash_program(offset,buffer,size,cycles) {
    if !esp_flash_size || offset<0 || size<0 || offset>esp_flash_size || size>esp_flash_size-offset || !esp_buffer_valid(buffer,size) {return -22;}
    let i=0;while i<size {let at=esp_flash_start+offset+i;let count=size-i;if count>64 {count=64;}if count>256-(at&255) {count=256-(at&255);}
        let error=esp_flash_enable(cycles);if error {return error;}error=esp_memory_command(0,2,at,3,buffer+i,0,count,cycles);if error {return error;}error=esp_flash_wait(cycles);if error {return error;}i=i+count;
    }return size;
}
fn esp_flash_erase(offset,size,cycles) {
    if !esp_flash_size || offset<0 || (offset&4095) || size<4096 || (size&4095) || offset>esp_flash_size || size>esp_flash_size-offset {return -22;}
    let i=0;while i<size {let error=esp_flash_enable(cycles);if error {return error;}error=esp_memory_command(0,0x20,esp_flash_start+offset+i,3,0,0,0,cycles);if error {return error;}error=esp_flash_wait(cycles);if error {return error;}i=i+4096;}return size;
}
