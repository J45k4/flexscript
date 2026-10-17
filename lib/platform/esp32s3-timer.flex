import "esp32s3-common.flex";
// Four 54-bit counters: id=group*2+timer. Caller selects prescaler and
// XTAL (40 MHz on S3 modules) or APB; no hidden CPU-frequency assumption.
fn esp_timer_base(id) {if id<0 || id>3 {return 0;}return 0x6001f000+(id/2)*4096+(id&1)*36;}
fn esp_timer_init(id,divider,xtal) {
    let base=esp_timer_base(id);if !base || divider<2 || divider>65535 || xtal<0 || xtal>1 {return -22;}
    esp_clock_enable(0,13+(id/2)*2);esp32_store32(base,(divider<<13)|(1<<30)|(xtal<<9));return esp_timer_set(id,0);
}
fn esp_timer_set(id,value) {
    let base=esp_timer_base(id);if !base || value<0 || value>18014398509481983 {return -22;}
    esp32_store32(base+24,value);esp32_store32(base+28,value>>32);esp32_store32(base+32,1);return 0;
}
fn esp_timer_read(id) {
    let base=esp_timer_base(id);if !base {return -22;}esp32_store32(base+12,1<<31);
    let result=esp_wait_mask(base+12,1<<31,0,1000000);if result {return result;}
    return esp32_load32(base+4)|((esp32_load32(base+8)&4194303)<<32);
}
fn esp_timer_start(id) {let base=esp_timer_base(id);if !base {return -22;}return esp_reg_update(base,1<<31,1<<31);}
fn esp_timer_stop(id) {let base=esp_timer_base(id);if !base {return -22;}return esp_reg_update(base,1<<31,0);}
fn esp_timer_alarm(id,value,repeat) {
    let base=esp_timer_base(id);if !base || value<1 || value>18014398509481983 || repeat<0 || repeat>1 {return -22;}
    esp32_store32(base+16,value);esp32_store32(base+20,value>>32);
    esp_reg_update(0x6001f070+(id/2)*4096,1<<(id&1),1<<(id&1));return esp_reg_update(base,(1<<29)|(1<<10),(repeat<<29)|(1<<10));
}
fn esp_timer_pending(id) {if !esp_timer_base(id) {return -22;}return (esp32_load32(0x6001f078+(id/2)*4096)>>(id&1))&1;}
fn esp_timer_ack(id,rearm) {
    let base=esp_timer_base(id);if !base {return -22;}esp32_store32(0x6001f07c+(id/2)*4096,1<<(id&1));
    if rearm {esp_reg_update(base,1<<10,1<<10);}return 0;
}
fn esp_timer_source(id) {if !esp_timer_base(id) {return -22;}return 50+(id/2)*3+(id&1);}
// Explicit packed-word API matches original-chip signatures; S3 remains54-bit.
fn esp_timer_set_words(id,low,high) {
    let base=esp_timer_base(id);if !base || low<0 || low>4294967295 || high<0 || high>4194303 {return -22;}
    esp32_store32(base+24,low);esp32_store32(base+28,high);esp32_store32(base+32,1);return 0;
}
fn esp_timer_read_words(id,buffer) {
    let base=esp_timer_base(id);if !base || (buffer&3) || !esp_buffer_valid(buffer,8) {return -22;}
    esp32_store32(base+12,1<<31);let result=esp_wait_mask(base+12,1<<31,0,1000000);if result {return result;}
    let low=esp32_load32(base+4);let high=esp32_load32(base+8)&4194303;esp32_store32(buffer,low);esp32_store32(buffer+4,high);return 0;
}
fn esp_timer_alarm_words(id,low,high,repeat) {
    let base=esp_timer_base(id);if !base || low<0 || low>4294967295 || high<0 || high>4194303 || repeat<0 || repeat>1 {return -22;}
    esp32_store32(base+16,low);esp32_store32(base+20,high);
    esp_reg_update(0x6001f070+(id/2)*4096,1<<(id&1),1<<(id&1));return esp_reg_update(base,(1<<29)|(1<<10),(repeat<<29)|(1<<10));
}
