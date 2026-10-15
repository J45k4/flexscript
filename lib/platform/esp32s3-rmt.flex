import "esp32s3-common.flex";
// RMT PIO: TX channels 0..3, RX channels 4..7, 48 32-bit symbols per
// channel. One symbol is (duration0[15],level0,duration1[15],level1).
fn esp_rmt_symbol(level0,ticks0,level1,ticks1) {
    if level0<0 || level0>1 || level1<0 || level1>1 || ticks0<1 || ticks0>32767 || ticks1<1 || ticks1>32767 {return -22;}
    return ticks0|(level0<<15)|(ticks1<<16)|(level1<<31);
}
fn esp_rmt_clock() {esp_clock_enable(0,9);esp32_store32(0x600160c0,(1<<31)|(1<<26)|(3<<24)|11);return 0;}
fn esp_rmt_tx_init(channel,pin,divider,idle) {
    if channel<0 || channel>3 || !esp_gpio_valid(pin) || divider<1 || divider>255 || idle<0 || idle>1 {return -22;}
    esp_rmt_clock();esp_gpio_route_output(pin,81+channel);esp32_store32(0x60016020+channel*4,(divider<<8)|(1<<16)|64|(idle<<5)|(1<<24));return 0;
}
fn esp_rmt_write(channel,symbols,count,cycles) {
    if channel<0 || channel>3 || count<1 || count>47 || !esp_buffer_valid(symbols,count*4) || (symbols&3) || cycles<1 || cycles>2147483647 {return -22;}
    let i=0;while i<count {let value=esp32_load32(symbols+i*4);if !(value&32767) || !((value>>16)&32767) {return -22;}i=i+1;}
    let config=0x60016020+channel*4;esp_reg_update(config,6,6);esp_reg_update(config,6,0);
    i=0;while i<count {esp32_store32(0x60016800+channel*192+i*4,esp32_load32(symbols+i*4));i=i+1;}
    esp32_store32(0x60016800+channel*192+count*4,0);esp32_store32(0x6001607c,1<<channel);esp_reg_update(config,(1<<24)|1,(1<<24)|1);
    let result=esp_wait_mask(0x60016070,1<<channel,1<<channel,cycles);if result {esp_reg_update(config,128,128);return result;}
    esp32_store32(0x6001607c,1<<channel);return count;
}
fn esp_rmt_rx_init(channel,pin,divider,idle_ticks,filter_ticks) {
    if channel<4 || channel>7 || !esp_gpio_valid(pin) || divider<1 || divider>255 || idle_ticks<1 || idle_ticks>32767 || filter_ticks<0 || filter_ticks>255 {return -22;}
    esp_rmt_clock();esp_gpio_input(pin,0);esp_gpio_route_input(pin,81+channel-4);
    let base=0x60016030+(channel-4)*8;esp32_store32(base,divider|(idle_ticks<<8)|(1<<24));let filter=0;if filter_ticks {filter=16|(filter_ticks<<5);}
    esp32_store32(base+4,filter|(1<<15)|8);return 0;
}
fn esp_rmt_read(channel,symbols,capacity,cycles) {
    if channel<4 || channel>7 || capacity<1 || capacity>48 || !esp_buffer_valid(symbols,capacity*4) || (symbols&3) || cycles<1 || cycles>2147483647 {return -22;}
    let config=0x60016034+(channel-4)*8;esp_reg_update(config,7,6);esp_reg_update(config,15,8);
    esp32_store32(0x6001607c,1<<channel);esp_reg_update(config,(1<<15)|1,(1<<15)|1);
    let result=esp_wait_mask(0x60016070,1<<channel,1<<channel,cycles);esp_reg_update(config,9,0);if result {return result;}
    let i=0;let complete=0;while i<capacity && !complete {
        let value=esp32_load32(0x60016800+channel*192+i*4);
        if !(value&32767) {complete=1;}else {esp32_store32(symbols+i*4,value);i=i+1;if !((value>>16)&32767) {complete=1;}}
    }esp32_store32(0x6001607c,1<<channel);return i;
}
