import "esp32s3-common.flex";
global esp_pwm_resolutions=0;
global esp_pwm_timers=0;
global esp_pwm_channels=0;
// LEDC: four shared timers, eight output channels. All timers use XTAL.
fn esp_pwm_timer(timer,hz,bits) {
    if timer<0 || timer>3 || hz<1 || hz>20000000 || bits<1 || bits>14 {return -22;}
    let steps=1<<bits;let divisor=(10240000000+hz*steps-1)/(hz*steps);
    if divisor<256 || divisor>262143 {return -22;}
    esp_clock_enable(0,11);esp_reg_update(0x600190d0,0x80000003,0x80000003);
    esp32_store32(0x600190a0+timer*8,(divisor<<4)|bits|(1<<25));
    esp_pwm_resolutions=(esp_pwm_resolutions&~(15<<(timer*4)))|(bits<<(timer*4));return 10240000000/divisor/steps;
}
fn esp_pwm_channel(channel,timer,pin) {
    if channel<0 || channel>7 || timer<0 || timer>3 || !esp_gpio_valid(pin) || !((esp_pwm_resolutions>>(timer*4))&15) {return -22;}
    esp_gpio_route_output(pin,73+channel);let base=0x60019000+channel*20;
    esp32_store32(base+4,0);esp32_store32(base+8,0);esp32_store32(base+12,0);esp32_store32(base,timer|4|16);
    esp_pwm_timers=(esp_pwm_timers&~(3<<(channel*2)))|(timer<<(channel*2));esp_pwm_channels=esp_pwm_channels|(1<<channel);return 0;
}
fn esp_pwm_duty(channel,duty) {
    if channel<0 || channel>7 || !(esp_pwm_channels&(1<<channel)) {return -22;}
    let timer=(esp_pwm_timers>>(channel*2))&3;let bits=(esp_pwm_resolutions>>(timer*4))&15;if duty<0 || duty>=(1<<bits) {return -22;}
    let base=0x60019000+channel*20;esp32_store32(base+8,duty<<4);esp32_store32(base+12,(1<<31)|(1<<30)|(1<<20)|(1<<10));esp_reg_update(base,20,20);return 0;
}
fn esp_pwm_stop(channel,level) {
    if channel<0 || channel>7 || level<0 || level>1 {return -22;}return esp_reg_update(0x60019000+channel*20,28,16|(level<<3));
}
