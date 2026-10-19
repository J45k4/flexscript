import "esp32-common.flex";
// Original ESP32 LEDC: timers0..3/channels0..7 high speed;4..7/8..15
// low speed. Both groups use80MHz APB; fractional divider has8 fraction bits.
global ep_timers=0;
global ep_channels=0;
fn ep_allocate() {
    if !ep_timers {let p=alloc(256);if p<=0{return -12;}let i=0;while i<256{store8(p+i,0);i=i+1;}ep_timers=p;}
    if !ep_channels {let p=alloc(512);if p<=0{return -12;}let i=0;while i<512{store8(p+i,0);i=i+1;}ep_channels=p;}return 0;
}
fn ep_timer_base(timer){return 0x3ff59140+(timer/4)*32+(timer&3)*8;}
fn ep_channel_base(channel){return 0x3ff59000+(channel/8)*160+(channel&7)*20;}
fn ep_channel_update(channel){if channel>=8{esp_reg_update(ep_channel_base(channel),16,16);}return 0;}
fn esp_pwm_timer(timer,hz,bits) {
    if timer<0 || timer>7 || hz<1 || hz>40000000 || bits<1 || bits>20{return -22;}
    let steps=1<<bits;let divisor=(20480000000+hz*steps-1)/(hz*steps);if divisor<256 || divisor>262143{return -22;}
    let ps=esp32_irq_save();let error=ep_allocate();if error{esp32_irq_restore(ps);return error;}
    let ch=0;while ch<16{let c=ep_channels+ch*32;if load64(c) && load64(c+16)==timer{esp32_irq_restore(ps);return -16;}ch=ch+1;}
    esp_clock_enable(0,11);esp_reg_update(0x3ff59000,1<<31,1<<31);esp_reg_update(0x3ff59190,1,1);let config=(divisor<<5)|bits|(1<<25);if timer>=4{config=config|(1<<26);}
    esp32_store32(ep_timer_base(timer),config|(1<<24));esp32_store32(ep_timer_base(timer),config);
    let state=ep_timers+timer*32;store64(state,1);store64(state+8,bits);store64(state+16,divisor);// Return the realized frequency rounded to the nearest whole Hz.
    esp32_irq_restore(ps);return (20480000000+divisor*steps/2)/(divisor*steps);
}
fn esp_pwm_channel(channel,timer,pin) {
    if channel<0 || channel>15 || timer<0 || timer>7 || channel/8!=timer/4 || !esp_gpio_valid(pin) || pin>=34{return -22;}
    let ps=esp32_irq_save();if !ep_timers || !load64(ep_timers+timer*32){esp32_irq_restore(ps);return -19;}let c=ep_channels+channel*32;if load64(c){esp32_irq_restore(ps);return -16;}
    let i=0;while i<16{let other=ep_channels+i*32;if load64(other) && load64(other+8)==pin{esp32_irq_restore(ps);return -16;}i=i+1;}
    let signal=71+(channel&7);if channel>=8{signal=79+(channel&7);}let base=ep_channel_base(channel);
    esp32_store32(base+4,0);esp32_store32(base+8,0);esp32_store32(base+12,0x40100400);let config=(timer&3)|4;if channel>=8{config=config|16;}esp_reg_update(base,31,config);esp_gpio_write(pin,0);esp_gpio_open_drain(pin,0);esp_gpio_route_output(pin,signal);
    esp_reg_update(0x3ff59188,1<<(8+channel),0);esp32_store32(0x3ff5918c,1<<(8+channel));store64(c,1);store64(c+8,pin);store64(c+16,timer);store64(c+24,0);esp32_irq_restore(ps);return 0;
}
fn esp_pwm_duty(channel,duty) {
    if channel<0 || channel>15{return -22;}let ps=esp32_irq_save();if !ep_channels || !load64(ep_channels+channel*32){esp32_irq_restore(ps);return -19;}let c=ep_channels+channel*32;let timer=load64(c+16);let bits=load64(ep_timers+timer*32+8);
    if duty<0 || duty>=(1<<bits){esp32_irq_restore(ps);return -22;}let base=ep_channel_base(channel);if esp32_load32(base+12)&(1<<31){esp32_irq_restore(ps);return -16;}esp32_store32(base+8,duty<<4);esp32_store32(base+12,0xc0100400);esp_reg_update(base,4,4);ep_channel_update(channel);store64(c+24,duty);esp32_irq_restore(ps);return 0;
}
fn esp_pwm_stop(channel,level) {
    if channel<0 || channel>15 || level<0 || level>1{return -22;}let ps=esp32_irq_save();if !ep_channels || !load64(ep_channels+channel*32){esp32_irq_restore(ps);return -19;}
    esp_reg_update(ep_channel_base(channel),12,level<<3);esp_reg_update(ep_channel_base(channel)+12,1<<31,0);ep_channel_update(channel);esp32_irq_restore(ps);return 0;
}
fn esp_pwm_channel_deinit(channel) {
    if channel<0 || channel>15{return -22;}let ps=esp32_irq_save();if !ep_channels || !load64(ep_channels+channel*32){esp32_irq_restore(ps);return 0;}let c=ep_channels+channel*32;
    esp_pwm_stop(channel,0);esp_gpio_input(load64(c+8),0);esp32_store32(ep_channel_base(channel)+12,0);store64(c,0);esp32_irq_restore(ps);return 0;
}
fn esp_pwm_timer_deinit(timer) {
    if timer<0 || timer>7{return -22;}let ps=esp32_irq_save();if !ep_timers || !load64(ep_timers+timer*32){esp32_irq_restore(ps);return 0;}
    let i=0;while i<16{let c=ep_channels+i*32;if load64(c) && load64(c+16)==timer{esp32_irq_restore(ps);return -16;}i=i+1;}
    let config=1<<23;if timer>=4{config=config|(1<<26);}esp32_store32(ep_timer_base(timer),config);store64(ep_timers+timer*32,0);let any=0;i=0;while i<8{any=any|load64(ep_timers+i*32);i=i+1;}if !any{esp_reg_update(0x3ff000c0,1<<11,0);}esp32_irq_restore(ps);return 0;
}
