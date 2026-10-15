import "esp32s3-common.flex";
// SD memory cards, native slot 0, one data wire, IDMAC 512-byte blocks.
// Caller supplies CLK/CMD/D0 pins and external pull-ups; no filesystem.
global esp_sd_descriptor=0;
global esp_sd_ready=0;
global esp_sd_rca=0;
global esp_sd_hc=0;
global esp_sd_blocks=0;
fn esp_sd_error(status) {if status&768 {return -110;}if status&0xb8c2 {return -5;}return 0;}
fn esp_sd_command(command,arg,flags,cycles) {
    if command<0 || command>63 || cycles<1 || cycles>2147483647 {return -22;}
    let error=esp_wait_mask(0x6002802c,1<<31,0,cycles);if error {return error;}
    esp32_store32(0x60028044,0xffffffff);esp32_store32(0x60028028,arg);esp32_store32(0x6002802c,command|flags|(1<<29)|(1<<31));
    let start=esp32_cycles();while !(esp32_load32(0x60028044)&4) {
        error=esp_sd_error(esp32_load32(0x60028044));if error {return error;}if ((esp32_cycles()-start)&4294967295)>=cycles {return -110;}
    }return esp_sd_error(esp32_load32(0x60028044));
}
fn esp_sd_clock(hz,cycles) {
    if hz<100000 || hz>20000000 || cycles<1 || cycles>2147483647 {return -22;}
    // XTAL / 2 module clock, then per-card / (2*N), N=0 bypass.
    let divisor=(20000000+hz*2-1)/(hz*2);if hz==20000000 {divisor=0;}
    esp32_store32(0x60028010,0);esp32_store32(0x60028008,divisor);esp32_store32(0x6002802c,(1<<31)|(1<<21)|(1<<13));
    let error=esp_wait_mask(0x6002802c,1<<31,0,cycles);if error {return error;}
    esp32_store32(0x60028010,1);esp32_store32(0x6002802c,(1<<31)|(1<<21)|(1<<13));return esp_wait_mask(0x6002802c,1<<31,0,cycles);
}
fn esp_sd_init(clk,cmd,d0,cycles) {
    if !esp_gpio_valid(clk) || !esp_gpio_valid(cmd) || !esp_gpio_valid(d0) || clk==cmd || clk==d0 || cmd==d0 || cycles<1 || cycles>2147483647 {return -22;}
    if !esp_sd_descriptor {esp_sd_descriptor=alloc(16);if esp_sd_descriptor<0 {return -12;}}esp_sd_ready=0;esp_sd_rca=0;esp_sd_blocks=0;esp_sd_hc=0;esp_clock_enable(1,7);
    esp_gpio_route_output(clk,172);esp_gpio_route_output(cmd,178);esp_gpio_route_input(cmd,178);esp_gpio_route_input(d0,180);esp_gpio_route_output(d0,180);esp32_store32(0x60004554+cmd*4,178);esp32_store32(0x60004554+d0*4,180);esp_gpio_pull(cmd,1);esp_gpio_pull(d0,1);
    esp32_store32(0x60028800,(1<<13)|(1<<17)|1);esp32_store32(0x60028000,7);
    let error=esp_wait_mask(0x60028000,7,0,cycles);if error {return error;}
    esp32_store32(0x60028004,1);esp32_store32(0x60028014,0xffffffff);esp32_store32(0x60028018,0);esp32_store32(0x60028024,0);esp32_store32(0x6002804c,(15<<16)|16);
    error=esp_sd_clock(400000,cycles);if error {return error;}
    error=esp_sd_command(0,0,1<<15,cycles);if error {return error;}
    let modern=1;error=esp_sd_command(8,0x1aa,320,cycles);
    if error== -110 {modern=0;}else if error {return error;}else if (esp32_load32(0x60028030)&4095)!=0x1aa {return -5;}
    let start=esp32_cycles();let ready=0;while !ready {
        error=esp_sd_command(55,0,320,cycles);if error {return error;}
        let arg=0x00ff8000;if modern {arg=arg|(1<<30);}error=esp_sd_command(41,arg,64,cycles);if error {return error;}
        let ocr=esp32_load32(0x60028030);if ocr&(1<<31) {ready=1;esp_sd_hc=(ocr>>30)&1;}else if ((esp32_cycles()-start)&4294967295)>=cycles {return -110;}
    }
    error=esp_sd_command(2,0,448,cycles);if error {return error;}
    error=esp_sd_command(3,0,320,cycles);if error {return error;}esp_sd_rca=esp32_load32(0x60028030)&0xffff0000;if !esp_sd_rca {return -5;}
    error=esp_sd_command(9,esp_sd_rca,448,cycles);if error {return error;}
    // Controller responses are the 128-bit CSD, least-significant word first.
    let top=esp32_load32(0x6002803c);let mid=esp32_load32(0x60028038);let low=esp32_load32(0x60028034);
    if ((top>>30)&3)==1 {esp_sd_blocks=(((mid&63)<<16)|(low>>16))+1;esp_sd_blocks=esp_sd_blocks*1024;}
    else {let c_size=((mid&1023)<<2)|(low>>30);let mult=(low>>15)&7;let read_bl=(mid>>16)&15;esp_sd_blocks=(c_size+1)*(1<<(mult+2))*(1<<read_bl)/512;}
    if esp_sd_blocks<1 {return -5;}
    error=esp_sd_command(7,esp_sd_rca,320,cycles);if error {return error;}
    if !esp_sd_hc {error=esp_sd_command(16,512,320,cycles);if error {return error;}}
    error=esp_sd_clock(10000000,cycles);if !error {esp_sd_ready=1;}return error;
}
fn esp_sd_block(block,buffer,write,cycles) {
    if !esp_sd_ready || block<0 || block>=esp_sd_blocks || !esp_buffer_valid(buffer,512) || write<0 || write>1 || cycles<1 || cycles>2147483647 {return -22;}
    let error=esp_wait_mask(0x60028048,1<<9,0,cycles);if error {return error;}
    esp_reg_update(0x60028000,2,2);error=esp_wait_mask(0x60028000,2,0,cycles);if error {return error;}
    esp32_store32(0x6002801c,512);esp32_store32(0x60028020,512);
    let arg=block;if !esp_sd_hc {arg=block*512;}let command=17;let flags=320|512|8192;if write {command=24;flags=flags|1024;}
    esp32_store32(esp_sd_descriptor+4,512);esp32_store32(esp_sd_descriptor+8,buffer);esp32_store32(esp_sd_descriptor+12,0);esp32_store32(esp_sd_descriptor,0x8000000c);
    esp32_store32(0x6002808c,0xffffffff);esp32_store32(0x60028088,esp_sd_descriptor);esp32_store32(0x60028080,128);esp_reg_update(0x60028000,(1<<25)|32,(1<<25)|32);
    error=esp_sd_command(command,arg,flags,cycles);if error {esp_sd_dma_stop();return error;}
    if esp32_load32(0x60028030)&0xfdffe008 {esp_sd_dma_stop();return -5;}
    let start=esp32_cycles();let done=0;while !done {
        let status=esp32_load32(0x60028044);error=esp_sd_error(status);
        if esp32_load32(0x6002808c)&0x34 {error= -5;}
        if error {esp_sd_dma_stop();return error;}
        if (status&8) && !(esp32_load32(esp_sd_descriptor)&(1<<31)) {done=1;}
        else if ((esp32_cycles()-start)&4294967295)>=cycles {esp_sd_dma_stop();return -110;}
    }
    esp_sd_dma_stop();esp32_store32(0x60028044,0xffffffff);if write {error=esp_wait_mask(0x60028048,1<<9,0,cycles);if error {return error;}}return 512;
}
fn esp_sd_dma_stop() {esp_reg_update(0x60028000,(1<<25)|32,0);esp32_store32(0x60028080,0);return 0;}
