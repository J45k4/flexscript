import "esp32s3-common.flex";
// GDMA, five RX/TX channel pairs. Internal uncached SRAM descriptors/buffers.
// Peripheral selectors: SPI2=0, SPI3=1, UHCI=2, I2S0=3, I2S1=4,
// LCD_CAM=5, AES=6, SHA=7, ADC=8, RMT=9. direction: RX=0, TX=1.
fn esp_dma_base(channel,direction) {if channel<0 || channel>4 || direction<0 || direction>1 {return 0;}return 0x6003f000+channel*192+direction*96;}
fn esp_dma_descriptor(desc,buffer,size,used,next,eof) {
    if !esp_buffer_valid(desc,16) || (desc&3) || !esp_buffer_valid(buffer,size) || (buffer&3) || size<1 || size>4092 || used<0 || used>size || eof<0 || eof>1 {return -22;}
    if next && (!esp_buffer_valid(next,16) || (next&3)) {return -22;}
    esp32_store32(desc+4,buffer);esp32_store32(desc+8,next);esp32_store32(desc+12,0);
    // Publish ownership last, after buffer/next pointers and a memory barrier.
    esp32_store32(desc,size|(used<<12)|(eof<<30)|(1<<31));return 0;
}
fn esp_dma_start(channel,direction,peripheral,descriptor) {
    let base=esp_dma_base(channel,direction);
    if !base || peripheral<0 || peripheral>9 || !esp_buffer_valid(descriptor,16) || (descriptor&3) {return -22;}
    esp_clock_enable(1,6);esp_reg_update(base,1,1);esp_reg_update(base,1,0);
    esp_reg_update(base,1<<12,1<<12);esp32_store32(base+20,0xffffffff);esp32_store32(base+72,peripheral);
    let start=1<<22;if direction {start=1<<21;esp_reg_update(base,1<<2,1<<2);}
    esp32_store32(base+32,(descriptor&1048575)|start);return 0;
}
fn esp_dma_wait(channel,direction,cycles) {
    let base=esp_dma_base(channel,direction);if !base || cycles<1 || cycles>2147483647 {return -22;}
    let start=esp32_cycles();let ready=0;let error_mask=8;let done_mask=2;if direction {error_mask=4;done_mask=8;}
    while !ready {
        let status=esp32_load32(base+8);if status&error_mask {esp_dma_stop(channel,direction);esp32_store32(base+20,0xffffffff);return -5;}if status&done_mask {ready=1;}
        else if ((esp32_cycles()-start)&4294967295)>=cycles {esp_dma_stop(channel,direction);return -110;}
    }esp32_store32(base+20,0xffffffff);return 0;
}
fn esp_dma_stop(channel,direction) {
    let base=esp_dma_base(channel,direction);if !base {return -22;}let bit=1<<21;if direction {bit=1<<20;}esp32_store32(base+32,bit);return 0;
}
