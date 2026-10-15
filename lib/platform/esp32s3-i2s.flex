import "esp32s3-dma.flex";
// Stereo Philips I2S master, 16/32-bit little-endian interleaved frames.
// Each controller is simplex; GDMA channel ownership belongs to the caller.
// init returns actual sample rate after XTAL fractional-clock quantization.
global esp_i2s_config=0;
fn esp_i2s_base(bus) {if bus<0 || bus>1 {return 0;}return 0x6000f000+bus*122880;}
fn esp_i2s_init(bus,direction,bck,ws,data,hz,bits) {
    let base=esp_i2s_base(bus);
    if !base || direction<0 || direction>1 || !esp_gpio_valid(bck) || !esp_gpio_valid(ws) || !esp_gpio_valid(data) || bck==ws || bck==data || ws==data || hz<8000 || hz>192000 || (bits!=16 && bits!=32) {return -22;}
    let divisor=(10240000000+hz*bits*2)/(hz*bits*4);if divisor<512 || divisor>65535 {return -22;}
    let clock=4;if bus {clock=21;}esp_clock_enable(0,clock);
    // Reset both directions before changing the shared MCLK source.
    esp32_store32(base+32,3);esp32_store32(base+36,3);esp32_store32(base+32,0);esp32_store32(base+36,0);
    let signal=26;if direction {signal=22;}if bus {signal=31;if direction {signal=28;}}
    esp_gpio_route_output(bck,signal);esp_gpio_route_output(ws,signal+1);if !bus && direction {esp_gpio_route_output(ws,24);}
    let sd=25;if bus {sd=30;}if direction {esp_gpio_route_output(data,sd);}else {esp_gpio_route_input(data,sd);}
    // direction RX=0, TX=1. MCLK selector is in the shared RX register.
    esp32_store32(base+48,0);esp32_store32(base+52,1<<29);
    let clk=base+48+direction*4;let frac=base+56+direction*4;
    let n=divisor&255;let x=0;let y=1;let z=0;let yn=0;
    if n {yn=n*2>256;z=n;if yn {z=256-n;}x=256/z-1;y=256%z;}
    let select=0;if !direction {select=1<<29;}
    // Required two-step divider sequence avoids the silicon double-division issue.
    esp32_store32(clk,(1<<26)|select|2);esp32_store32(frac,512);esp32_store32(frac,(yn<<27)|(x<<18)|(y<<9)|z);esp_reg_update(clk,255,divisor>>8);
    let conf=base+32+direction*4;let conf1=base+40+direction*4;
    esp32_store32(conf1,(bits-1)|128|((bits-1)<<13)|((bits-1)<<18)|((bits-1)<<24)|(1<<29));
    esp32_store32(base+80+direction*4,65539); // two active slots
    esp32_store32(conf,(1<<19)|(1<<15)|(1<<12)|(1<<8));
    let packed=bits|(direction<<6)|128;esp_i2s_config=(esp_i2s_config&~(255<<(bus*8)))|(packed<<(bus*8));return 10240000000/divisor/(bits*4);
}
fn esp_i2s_transfer(bus,direction,channel,descriptor,buffer,size,cycles) {
    let base=esp_i2s_base(bus);let cfg=(esp_i2s_config>>(bus*8))&255;
    if !base || direction<0 || direction>1 || !(cfg&128) || ((cfg>>6)&1)!=direction || channel<0 || channel>4 || size<1 || size>4092 || size%((cfg&63)/4) || cycles<1 || cycles>2147483647 {return -22;}
    let used=0;if direction {used=size;}let error=esp_dma_descriptor(descriptor,buffer,size,used,0,1);if error {return error;}
    let conf=base+32+direction*4;esp_reg_update(conf,7,3);esp_reg_update(conf,7,0);
    if !direction {esp32_store32(base+0x64,size);}
    error=esp_dma_start(channel,direction,3+bus,descriptor);if error {return error;}
    esp_reg_update(conf,260,260);error=esp_dma_wait(channel,direction,cycles);
    if !error && direction {error=esp_wait_mask(base+108,1,1,cycles);}
    esp_reg_update(conf,260,256);esp_dma_stop(channel,direction);if error {return error;}return size;
}
