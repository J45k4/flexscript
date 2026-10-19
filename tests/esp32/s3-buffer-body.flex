import "../../lib/platform/esp32s3-spi.flex";
global sb_checks=0;
fn sb_run(known) {
    let state=esp32_state();let end=0x3fcd0000;
    if !known {sb_checks=sb_checks+2;if esp_buffer_valid(0x3fcb1000,1) || esp_buffer_valid(end,0) {return 1;}return 0;}
    if !esp_buffer_valid(state+24,0) || !esp_buffer_valid(state+24,1) || !esp_buffer_valid(end-1,1) || !esp_buffer_valid(end,0) {return 2;}sb_checks=sb_checks+4;
    if esp_buffer_valid(state,1) || esp_buffer_valid(state+16,4) || esp_buffer_valid(state+23,1) || esp_buffer_valid(state+24,-1) || esp_buffer_valid(end,1) || esp_buffer_valid(end+1,0) {return 3;}sb_checks=sb_checks+6;
    if esp_buffer_valid(-1,1) || esp_buffer_valid(9223372036854775807,1) || esp_buffer_valid(state+24,9223372036854775807) || esp_buffer_valid(0x3fc90000,4) || esp_buffer_valid(0x42000000,1) || esp_buffer_valid(0x3c400000,1) {return 4;}sb_checks=sb_checks+6;
    let first=0x3fcc0000;if state==0x3fcc0000 {first=0x3fcc4000;}else if state==0x3fca8000 {first=0x3fcb0000;}
    if !esp_buffer_valid(first,16) || !esp_buffer_valid(state+24,end-state-24) || esp_buffer_valid(state+24,end-state-23) {return 5;}sb_checks=sb_checks+3;
    // Invalid descriptors must return before FIFO access or RX writes.
    if esp_spi_transfer(2,state+16,0,4,100)!= -22 || esp_spi_transfer(2,0,state+16,4,100)!= -22 || esp_spi_transfer(2,0x3fc90000,0,4,100)!= -22 || esp_spi_transfer(2,0,end-3,4,100)!= -22 {return 6;}sb_checks=sb_checks+4;
    return 0;
}
