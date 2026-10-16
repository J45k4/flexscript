import "esp32-common.flex";
// Four 64-bit counters: id=group*2+timer. Caller selects prescaler and
// APB only (xtal parameter must be zero); no hidden CPU-frequency assumption.
// Signed-value set/alarm accept0..INT64_MAX (alarm excludes0). read returns
// raw signed64-bit bits; upper-half counts can look like negative errno values.
// Use the explicit low/high32-bit APIs for all64 bits and separate read status.
fn esp_timer_base(id) {if id<0 || id>3 {return 0;}return 0x3ff5f000+(id/2)*4096+(id&1)*36;}
fn esp_timer_init(id,divider,xtal) {
    let base=esp_timer_base(id);if !base || divider<2 || divider>65535 || xtal!=0 {return -22;}
    esp_clock_enable(0,13+(id/2)*2);esp32_store32(base,(divider<<13)|(1<<30)|(1<<11));return esp_timer_set(id,0);
}
fn esp_timer_set(id,value) {
    let base=esp_timer_base(id);if !base || value<0 {return -22;}
    esp32_store32(base+24,value);esp32_store32(base+28,value>>32);esp32_store32(base+32,1);return 0;
}
fn esp_timer_read(id) {
    let base=esp_timer_base(id);if !base {return -22;}esp32_store32(base+12,1<<31);
    let result=esp_wait_mask(base+12,1<<31,0,1000000);if result {return result;}
    return esp32_load32(base+4)|((esp32_load32(base+8)&4294967295)<<32);
}
fn esp_timer_start(id) {let base=esp_timer_base(id);if !base {return -22;}return esp_reg_update(base,1<<31,1<<31);}
fn esp_timer_stop(id) {let base=esp_timer_base(id);if !base {return -22;}return esp_reg_update(base,1<<31,0);}
fn esp_timer_alarm(id,value,repeat) {
    let base=esp_timer_base(id);if !base || value<1 || repeat<0 || repeat>1 {return -22;}
    esp32_store32(base+16,value);esp32_store32(base+20,value>>32);
    esp_reg_update(0x3ff5f098+(id/2)*4096,1<<(id&1),1<<(id&1));return esp_reg_update(base,(1<<29)|(1<<10),(repeat<<29)|(1<<10));
}
fn esp_timer_pending(id) {if !esp_timer_base(id) {return -22;}return (esp32_load32(0x3ff5f0a0+(id/2)*4096)>>(id&1))&1;}
fn esp_timer_ack(id,rearm) {
    let base=esp_timer_base(id);if !base {return -22;}esp32_store32(0x3ff5f0a4+(id/2)*4096,1<<(id&1));
    if rearm {esp_reg_update(base,1<<10,1<<10);}return 0;
}
fn esp_timer_source(id) {if !esp_timer_base(id) {return -22;}return 14+(id/2)*4+(id&1);}
// All32-bit words are zero-extended Flexscript values,not signed i32 values.
fn esp_timer_set_words(id,low,high) {
    let base=esp_timer_base(id);if !base || low<0 || low>4294967295 || high<0 || high>4294967295 {return -22;}
    esp32_store32(base+24,low);esp32_store32(base+28,high);esp32_store32(base+32,1);return 0;
}
// One latched snapshot into packed[low:u32,high:u32]. No destination writes
// on invalid arguments or timeout. The caller owns this aligned DRAM buffer.
fn esp_timer_read_words(id,buffer) {
    let base=esp_timer_base(id);if !base || (buffer&3) || !esp_buffer_valid(buffer,8) {return -22;}
    esp32_store32(base+12,1<<31);let result=esp_wait_mask(base+12,1<<31,0,1000000);if result {return result;}
    let low=esp32_load32(base+4);let high=esp32_load32(base+8);esp32_store32(buffer,low);esp32_store32(buffer+4,high);return 0;
}
// Absolute full-width threshold,including0 for modulo wrap. repeat0/1.
fn esp_timer_alarm_words(id,low,high,repeat) {
    let base=esp_timer_base(id);if !base || low<0 || low>4294967295 || high<0 || high>4294967295 || repeat<0 || repeat>1 {return -22;}
    esp32_store32(base+16,low);esp32_store32(base+20,high);
    esp_reg_update(0x3ff5f098+(id/2)*4096,1<<(id&1),1<<(id&1));return esp_reg_update(base,(1<<29)|(1<<10),(repeat<<29)|(1<<10));
}
