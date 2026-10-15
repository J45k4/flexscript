import "esp32s3-common.flex";
// Raw, uncalibrated 12-bit RTC one-shot conversions. No millivolt claim.
// unit 1 channels 0..9 -> GPIO1..10; unit 2 -> GPIO11..20.
fn esp_adc_init(unit,channel,attenuation) {
    if unit<1 || unit>2 || channel<0 || channel>9 || attenuation<0 || attenuation>3 {return -22;}
    let pin=channel+1+(unit-1)*10;esp_gpio_input(pin,0);
    esp_reg_update(0x60008484+pin*4,(1<<19)|(3<<17)|(1<<13)|(3<<27),1<<19);
    esp_clock_enable(0,28);esp_reg_update(0x60040000,(3<<27)|64,(3<<27)|64);esp_reg_update(0x6000883c,0xe0000000,0xe0000000);
    let delta=(unit-1)*36;esp_reg_update(0x60008800+delta,255|(1<<(27+unit)),2);
    esp_reg_update(0x60008810+delta,1<<31,0);esp_reg_update(0x6000880c+delta,(1<<31)|(1<<18),(1<<31)|(1<<18));
    esp_reg_update(0x60008814+delta,3<<(channel*2),attenuation<<(channel*2));return 0;
}
fn esp_adc_read(unit,channel,cycles) {
    if unit<1 || unit>2 || channel<0 || channel>9 || cycles<1 || cycles>2147483647 {return -22;}
    let base=0x6000880c+(unit-1)*36;
    if unit==1 {let idle=esp_wait_mask(0x60008840,255<<22,0,cycles);if idle {return idle;}}
    esp_reg_update(base,(4095<<19)|(1<<17),1<<(channel+19));esp_reg_update(base,1<<17,1<<17);
    let error=esp_wait_mask(base,1<<16,1<<16,cycles);if error {return error;}return esp32_load32(base)&4095;
}
