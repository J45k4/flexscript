import "esp32.flex";
// Register definitions are from ESP-IDF v5.5.1, original ESP32 only.
// Shared errno results: EINVAL=-22, ENOMEM=-12, EIO=-5, ETIMEDOUT=-110.
fn esp_reg_update(address,mask,value) {esp32_store32(address,(esp32_load32(address)&~mask)|(value&mask));return 0;}
fn esp_clock_enable(bank,bit) {
    if bank<0 || bank>0 || bit<0 || bit>31 {return -22;}
    esp_reg_update(0x3ff000c0,1<<bit,1<<bit);esp_reg_update(0x3ff000c4,1<<bit,0);return 0;
}
fn esp_wait_mask(address,mask,value,cycles) {
    if cycles<1 || cycles>2147483647 {return -22;}
    let start=esp32_cycles();while (esp32_load32(address)&mask)!=value {
        if ((esp32_cycles()-start)&4294967295)>=cycles {return -110;}
    }return 0;
}
fn esp_buffer_valid(pointer,size) {return size>=0 && pointer>=0x3ffb0010 && pointer<=0x3ffd0000 && size<=0x3ffd0000-pointer;}
