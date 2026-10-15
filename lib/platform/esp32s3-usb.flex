import "esp32s3-common.flex";
// DWC2 full-speed OTG controller, polling PIO. Internal PHY GPIO19/20.
// Shares the PHY with Serial/JTAG; one mode at a time. No hub/HS/isochronous.
global esp_usb_mode=0;
fn esp_usb_fifo_write(endpoint,buffer,size) {
    let i=0;while i<size {let word=0;let j=0;while j<4 {if i+j<size {word=word|(load8(buffer+i+j)<<(j*8));}j=j+1;}esp32_store32(0x60081000+endpoint*4096,word);i=i+4;}return 0;
}
fn esp_usb_fifo_read(buffer,capacity,size) {
    let i=0;while i<size {let word=esp32_load32(0x60081000);let j=0;while j<4 {if i+j<size && i+j<capacity {store8(buffer+i+j,word>>(j*8));}j=j+1;}i=i+4;}if size>capacity {return -90;}return size;
}
fn esp_usb_core(host,cycles) {
    if host<0 || host>1 || cycles<1 || cycles>2147483647 {return -22;}
    esp_usb_mode=0;esp_clock_enable(0,23);esp_reg_update(0x60038018,1<<14,0);esp_reg_update(0x60008120,3<<19,3<<19);
    esp32_store32(0x60039000,(1<<31)|(1<<22)|(1<<20)|(1<<19)|(1<<18));
    let select=1<<30;if host {select=1<<29;}esp32_store32(0x6008000c,select|64|(5<<10));
    // Mode switching requires PHY settling before the core soft reset.
    esp_delay_cycles(2000000);let error=esp_wait_mask(0x60080010,1<<31,1<<31,cycles);if error {return error;}
    esp32_store32(0x60080010,1);error=esp_wait_mask(0x60080010,1,0,cycles);if error {return error;}
    esp_delay_cycles(1000);esp32_store32(0x60080008,0);esp32_store32(0x60080018,0);esp32_store32(0x60080014,0xffffffff);
    // Require at least 192 FIFO words; never size FIFOs beyond hardware depth.
    if ((esp32_load32(0x6008004c)>>16)&65535)<192 {return -19;}
    esp32_store32(0x60080024,128);esp32_store32(0x60080028,(16<<16)|128);
    esp32_store32(0x60080010,(16<<6)|32);error=esp_wait_mask(0x60080010,32,0,cycles);if error {return error;}
    esp32_store32(0x60080010,16);return esp_wait_mask(0x60080010,16,0,cycles);
}
fn esp_usb_endpoint(endpoint,direction,kind,packet) {
    if esp_usb_mode!=1 || endpoint<0 || endpoint>3 || direction<0 || direction>1 || kind<0 || kind>3 || kind==1 || packet<1 || packet>64 || (!endpoint && (packet!=64 || kind)) || (endpoint && !kind) {return -22;}
    let base=0x60080b00;if direction {base=0x60080900;}base=base+endpoint*32;
    let config=(1<<15)|(kind<<18);if endpoint {config=config|packet|(1<<28);if direction {config=config|(endpoint<<22);}}
    esp32_store32(base,config);esp32_store32(base+8,0xffffffff);return 0;
}
fn esp_usb_device_reset() {
    if esp_usb_mode!=1 {return -22;}esp_reg_update(0x60080800,127<<4,0);
    let i=0;while i<4 {esp32_store32(0x60080900+i*32,1<<27);esp32_store32(0x60080b00+i*32,1<<27);esp32_store32(0x60080908+i*32,0xffffffff);esp32_store32(0x60080b08+i*32,0xffffffff);i=i+1;}
    esp_usb_endpoint(0,1,0,64);esp_usb_endpoint(0,0,0,64);return esp_usb_device_arm(0);
}
fn esp_usb_device_init(cycles) {
    let error=esp_usb_core(0,cycles);if error {return error;}
    // Force peripheral ID/VBUS-valid inputs high, session-end low.
    esp32_store32(0x6000423c,0xb8);esp32_store32(0x60004244,0xb8);esp32_store32(0x60004248,0xb8);esp32_store32(0x6000424c,0xb0);
    esp32_store32(0x60080804,2);esp32_store32(0x60080800,3);esp32_store32(0x60080e00,0);
    let i=1;while i<4 {esp32_store32(0x60080100+i*4,(16<<16)|(128+i*16));i=i+1;}
    esp_usb_mode=1;esp_usb_device_reset();esp32_store32(0x60080804,0);return 0;
}
fn esp_usb_device_arm(endpoint) {
    if esp_usb_mode!=1 || endpoint<0 || endpoint>3 {return -22;}let base=0x60080b00+endpoint*32;let size=64|(1<<19);if !endpoint {size=size|(3<<29);}
    esp32_store32(base+16,size);esp_reg_update(base,(1<<21)|(1<<27)|(1<<31)|(1<<26),(1<<31)|(1<<26));return 0;
}
fn esp_usb_device_send(endpoint,buffer,size,cycles) {
    if esp_usb_mode!=1 || endpoint<0 || endpoint>3 || size<0 || size>64 || !esp_buffer_valid(buffer,size) || cycles<1 || cycles>2147483647 {return -22;}
    let base=0x60080900+endpoint*32;if !(esp32_load32(base)&(1<<15)) {return -22;}
    let error=esp_wait_mask(base,1<<31,0,cycles);if error {return error;}esp32_store32(base+8,0xffffffff);esp32_store32(base+16,(1<<19)|size);
    esp_reg_update(base,(1<<21)|(1<<27)|(1<<31)|(1<<26),(1<<31)|(1<<26));if size {
        let start=esp32_cycles();while (esp32_load32(base+24)&65535)<(size+3)/4 {if ((esp32_cycles()-start)&4294967295)>=cycles {return -110;}}
        esp_usb_fifo_write(endpoint,buffer,size);
    }
    // Caller can poll completion; never block EP0 waiting for the host's next request.
    return size;
}
fn esp_usb_device_receive(buffer,capacity) {
    if esp_usb_mode!=1 || capacity<0 || !esp_buffer_valid(buffer,capacity) {return -22;}
    let status=esp32_load32(0x60080014);if status&(1<<12) {esp32_store32(0x60080014,1<<12);esp_usb_device_reset();return -104;}
    if status&(1<<13) {esp32_store32(0x60080014,1<<13);esp_reg_update(0x60080900,3,0);}
    if !(status&16) {return -11;}let packet=esp32_load32(0x60080020);let size=(packet>>4)&2047;let result=esp_usb_fifo_read(buffer,capacity,size);if result<0 {return result;}return packet;
}
fn esp_usb_device_address(address) {if esp_usb_mode!=1 || address<0 || address>127 {return -22;}return esp_reg_update(0x60080800,127<<4,address<<4);}
fn esp_usb_device_stall(endpoint,direction) {if esp_usb_mode!=1 || endpoint<0 || endpoint>3 || direction<0 || direction>1 {return -22;}let base=0x60080b00;if direction {base=0x60080900;}return esp_reg_update(base+endpoint*32,1<<21,1<<21);}
// Host mode needs a board-provided, current-limited 5V VBUS supply.
// This API controls the controller only; it does not choose or drive a VBUS GPIO.
fn esp_usb_host_init(cycles) {
    let error=esp_usb_core(1,cycles);if error {return error;}esp32_store32(0x6000423c,0xb0);esp32_store32(0x60004240,0xb8);esp32_store32(0x60004248,0xb8);esp32_store32(0x6000424c,0xb0);
    esp32_store32(0x60080400,1);esp32_store32(0x60080404,48000);esp32_store32(0x60080440,1<<12);esp_usb_mode=2;return 0;
}
fn esp_usb_host_reset(cycles) {
    if esp_usb_mode!=2 || cycles<1 || cycles>2147483647 {return -22;}let error=esp_wait_mask(0x60080440,1,1,cycles);if error {return error;}
    // W1C change bits and enable are never echoed back accidentally.
    let port=esp32_load32(0x60080440)&~0x2e;esp32_store32(0x60080440,port|(1<<8));esp_delay_cycles(4000000);esp32_store32(0x60080440,port&~(1<<8));esp_delay_cycles(4000000);
    error=esp_wait_mask(0x60080440,4,4,cycles);if error {return error;}if ((esp32_load32(0x60080440)>>17)&3)!=1 {return -95;}return 0;
}
fn esp_usb_host_halt(cycles) {
    esp_reg_update(0x60080500,(1<<31)|(1<<30),(1<<31)|(1<<30));let error=esp_wait_mask(0x60080500,1<<31,0,cycles);esp32_store32(0x60080508,0xffffffff);return error;
}
fn esp_usb_host_packet(address,endpoint,direction,kind,pid,packet,buffer,size,cycles) {
    // One full-speed packet through channel 0; caller tracks endpoint data PID.
    if esp_usb_mode!=2 || address<0 || address>127 || endpoint<0 || endpoint>15 || direction<0 || direction>1 || (kind!=0 && kind!=2) || (pid!=0 && pid!=2 && pid!=3) || (packet!=8 && packet!=16 && packet!=32 && packet!=64) || size<0 || size>packet || !esp_buffer_valid(buffer,size) || cycles<1 || cycles>2147483647 {return -22;}
    if !(esp32_load32(0x60080440)&4) {return -19;}let channel=0x60080500;
    esp32_store32(channel+8,0xffffffff);esp32_store32(channel+12,0);esp32_store32(channel+16,(pid<<29)|(1<<19)|size);
    esp32_store32(channel,packet|(endpoint<<11)|(direction<<15)|(kind<<18)|(1<<20)|(address<<22)|(1<<31));
    if !direction && size {esp_usb_fifo_write(0,buffer,size);}let start=esp32_cycles();let count=0;
    while 1 {
        let interrupt=esp32_load32(channel+8);
        if interrupt&8 {esp_usb_host_halt(cycles);return -32;}if interrupt&16 {esp_usb_host_halt(cycles);return -11;}if interrupt&0x784 {esp_usb_host_halt(cycles);return -5;}
        if esp32_load32(0x60080014)&16 {let status=esp32_load32(0x60080020);let bytes=(status>>4)&2047;let result=esp_usb_fifo_read(buffer+count,size-count,bytes);if result<0 {esp_usb_host_halt(cycles);return result;}count=count+bytes;}
        if interrupt&1 {esp32_store32(channel+8,0xffffffff);if direction {return count;}return size;}
        if ((esp32_cycles()-start)&4294967295)>=cycles {esp_usb_host_halt(cycles);return -110;}
    }return -5;
}
