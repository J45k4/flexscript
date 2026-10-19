import "esp32s3-common.flex";
import "esp32-analog-state.flex";
// ESP32-S3 RTC one-shot ADC1/2: raw12-bit counts; no voltage calibration.
// Init owns only the requested pad/configuration. Reads mask CPU0 interrupts,
// publish analog ownership, and restore shared fields on every completion path.
global s3a_state=0;
global s3a_saved_count=0;
fn s3a_index(unit,channel) {if unit<1 || unit>2 || channel<0 || channel>9 {return -1;}return (unit-1)*10+channel;}
fn esp_adc_pin(unit,channel) {if s3a_index(unit,channel)<0 {return -22;}return (unit-1)*10+channel+1;}
fn s3a_controller_busy(unit) {let delta=(unit-1)*36;return (esp32_load32(0x60008810+delta)&(1<<31)) || (esp32_load32(0x6000880c+delta)&(1<<17)) || (esp32_load32(0x60040000)&2) || (esp32_load32(0x60040004)&(1<<24)) || (esp32_load32(0x600c0020)&(1<<28));}
fn s3a_conflict(unit) {let irq=1<<11;if unit==2 {irq=1<<14;}return esp_adc_busy || esp32_load32(esp32_state()+16) || (unit==2 && (esp_radio_owner || esp_radio_phy_refs || esp_radio_phy_clock_refs)) || (esp32_load32(0x60008040)&irq) || (esp32_load32(0x600080fc)&(1<<31)) || (esp32_load32(0x60008100)&(3<<30)) || s3a_controller_busy(unit);}
fn s3a_pad_held(pin) {return ((esp32_load32(0x600080d8)|esp32_load32(0x600080dc))&(1<<pin)) || (esp32_load32(0x60008088)&(1<<21)) || (esp32_load32(0x60008094)&(1<<15));}
fn esp_adc_init(unit,channel,attenuation) {
    let index=s3a_index(unit,channel);if index<0 || attenuation<0 || attenuation>3 {return -22;}let ps=esp32_irq_save();let pin=esp_adc_pin(unit,channel);
    if s3a_conflict(unit) || s3a_pad_held(pin) {esp32_irq_restore(ps);return -16;}
    if !s3a_state {let p=alloc(640);if p<=0 {esp32_irq_restore(ps);return -12;}let i=0;while i<640 {store8(p+i,0);i=i+1;}s3a_state=p;}
    esp_gpio_input(pin,0);esp_reg_update(0x60009004+pin*4,1<<9,0);esp32_store32(0x60008414,1<<(pin+10));
    esp_reg_update(0x60008484+pin*4,(1<<19)|(3<<17)|(1<<13)|(3<<27),1<<19);
    store64(s3a_state+index*16,1);store64(s3a_state+index*16+8,attenuation);esp32_irq_restore(ps);return 0;
}
fn s3a_patch(address,mask,value) {
    let p=s3a_state+320+s3a_saved_count*24;let old=esp32_load32(address);
    store64(p,address);store64(p+8,mask);store64(p+16,old);s3a_saved_count=s3a_saved_count+1;esp_reg_update(address,mask,value);return 0;
}
fn s3a_restore() {while s3a_saved_count {s3a_saved_count=s3a_saved_count-1;let p=s3a_state+320+s3a_saved_count*24;esp_reg_update(load64(p),load64(p+8),load64(p+16));}return 0;}
fn s3a_expired(start,cycles) {return ((esp32_cycles()-start)&4294967295)>=cycles;}
fn esp_adc_read(unit,channel,cycles) {
    let index=s3a_index(unit,channel);if index<0 || cycles<1 || cycles>2147483647 {return -22;}let ps=esp32_irq_save();
    if s3a_conflict(unit) {esp32_irq_restore(ps);return -16;}if !s3a_state || !load64(s3a_state+index*16) {esp32_irq_restore(ps);return -19;}
    if s3a_pad_held(esp_adc_pin(unit,channel)) {esp32_irq_restore(ps);return -16;}
    let delta=(unit-1)*36;let control=0x6000880c+delta;let mux=0x60008810+delta;
    esp_adc_busy=unit;s3a_saved_count=0;let start=esp32_cycles();
    s3a_patch(0x600c0018,1<<28,1<<28);s3a_patch(0x60040000,(3<<27)|64,(3<<27)|64);s3a_patch(0x6000883c,0xe0000000,0xe0000000);
    let invert=1<<28;let interrupt=1<<29;if unit==2 {invert=1<<29;interrupt=1<<30;}
    s3a_patch(0x60008800+delta,255|invert|interrupt,1);
    s3a_patch(0x60008814+delta,3<<(channel*2),load64(s3a_state+index*16+8)<<(channel*2));
    s3a_patch(mux,1<<31,0);
    if unit==2 {s3a_patch(0x60040038,0x1ffc,(1<<12)|(1<<10)|(2<<8)|8);}
    s3a_patch(control,(1<<31)|(4095<<19)|(1<<18)|(1<<17),(1<<31)|(1<<18)|(1<<(channel+19)));
    let error=0;
    if unit==1 {while !error && (esp32_load32(0x60008840)&(255<<22)) {if s3a_expired(start,cycles) {error= -110;}}}
    if !error && s3a_expired(start,cycles) {error= -110;}
    if !error {
        esp_reg_update(control,1<<17,0);esp_reg_update(control,1<<17,1<<17);
        while !error && !(esp32_load32(control)&(1<<16)) {if s3a_expired(start,cycles) {error= -110;}}
    }
    let result=error;if !error {let raw=esp32_load32(control)&65535;result=raw&4095;if unit==2 && (raw&0xc000) {result= -11;}}
    // Stop the request before restoring its controller, arbiter and clocks.
    esp_reg_update(control,(1<<17)|(4095<<19),0);s3a_restore();esp_adc_busy=0;esp32_irq_restore(ps);return result;
}
fn esp_adc_deinit(unit,channel) {
    let index=s3a_index(unit,channel);if index<0 {return -22;}let ps=esp32_irq_save();
    if s3a_conflict(unit) {esp32_irq_restore(ps);return -16;}if !s3a_state || !load64(s3a_state+index*16) {esp32_irq_restore(ps);return 0;}
    let pin=esp_adc_pin(unit,channel);if s3a_pad_held(pin) {esp32_irq_restore(ps);return -16;}
    esp_gpio_input(pin,0);store64(s3a_state+index*16,0);esp32_irq_restore(ps);return 0;
}
