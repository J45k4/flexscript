import "esp32-common.flex";
// Original ESP32:8 bidirectional channels. TX uses one64-word block; RX
// can reserve1..8 contiguous blocks without overlapping another owner.
// APB80MHz, divider1..256. Non-FIFO memory avoids the documented FIFO hazard.
global er_states=0;
global er_memory_mask=0;
fn er_state(channel){if channel<0 || channel>7 || !er_states{return 0;}return er_states+channel*64;}
fn er_config(channel){return 0x3ff56020+channel*8;}
fn er_memory(channel){return 0x3ff56800+channel*256;}
fn er_events(channel){return (7<<(channel*3))|(1<<(24+channel));}
fn esp_rmt_symbol(level0,ticks0,level1,ticks1){if level0<0 || level0>1 || level1<0 || level1>1 || ticks0<1 || ticks0>32767 || ticks1<1 || ticks1>32767{return -22;}return ticks0|(level0<<15)|(ticks1<<16)|(level1<<31);}
fn esp_rmt_clock(){esp_clock_enable(0,9);esp_reg_update(0x3ff56020,0xc0000000,0x80000000);esp_reg_update(0x3ff560f0,3,1);return 0;}
fn er_allocate(){if !er_states{let p=alloc(512);if p<=0{return -12;}let i=0;while i<512{store8(p+i,0);i=i+1;}er_states=p;}return 0;}
fn er_ready(channel,state){if load64(state+8)==3 && (esp32_load32(0x3ff560a0)&(1<<(channel*3))){store64(state+8,0);esp32_store32(0x3ff560ac,er_events(channel));}if load64(state+8){return -16;}return 0;}
fn er_init(channel,pin,divider,mode,threshold,filter,idle,blocks) {
    if channel<0 || channel>7 || !esp_gpio_valid(pin) || (mode==1 && pin>=34) || divider<1 || divider>256 || blocks<1 || blocks>8-channel{return -22;}
    let ps=esp32_irq_save();let error=er_allocate();if error{esp32_irq_restore(ps);return error;}let state=er_state(channel);let mask=((1<<blocks)-1)<<channel;if load64(state) || load64(state+8) || (er_memory_mask&mask){esp32_irq_restore(ps);return -16;}
    let i=0;while i<8{let s=er_state(i);if load64(s) && load64(s+16)==pin{esp32_irq_restore(ps);return -16;}i=i+1;}
    esp_rmt_clock();let c0=(divider&255)|(threshold<<8)|(blocks<<24);if !channel{c0=c0|(1<<31);}let c1=1<<17;
    if mode==1{c1=c1|(1<<19)|(idle<<18);esp_gpio_write(pin,idle);esp_gpio_route_output(pin,87+channel);esp_gpio_open_drain(pin,0);}else{c1=c1|(1<<5);if filter{c1=c1|128|(filter<<8);}esp_gpio_input(pin,0);esp_gpio_route_input(pin,83+channel);}
    esp32_store32(er_config(channel),c0);esp32_store32(er_config(channel)+4,c1|(1<<16)|28);esp32_store32(er_config(channel)+4,c1);esp_reg_update(0x3ff560a8,er_events(channel),0);esp32_store32(0x3ff560ac,er_events(channel));
    store64(state,mode);store64(state+8,0);store64(state+16,pin);store64(state+24,c0);store64(state+32,c1);store64(state+40,divider);store64(state+48,blocks);store64(state+56,mask);er_memory_mask=er_memory_mask|mask;esp32_irq_restore(ps);return 0;
}
fn esp_rmt_tx_init(channel,pin,divider,idle){if idle<0 || idle>1{return -22;}return er_init(channel,pin,divider,1,0,0,idle,1);}
fn esp_rmt_rx_init_blocks(channel,pin,divider,idle_ticks,filter_ticks,blocks){if idle_ticks<1 || idle_ticks>32767 || filter_ticks<0 || filter_ticks>255{return -22;}return er_init(channel,pin,divider,2,idle_ticks,filter_ticks,0,blocks);}
fn esp_rmt_rx_init(channel,pin,divider,idle_ticks,filter_ticks){return esp_rmt_rx_init_blocks(channel,pin,divider,idle_ticks,filter_ticks,1);}
fn esp_rmt_tick_hz(channel){let state=er_state(channel);if !state || !load64(state){return -19;}return 80000000/load64(state+40);}
fn esp_rmt_stop(channel) {
    if channel<0 || channel>7{return -22;}let state=er_state(channel);if !state || !load64(state){return 0;}let mode=load64(state);let config=er_config(channel)+4;
    if mode==2{esp_reg_update(config,2,0);esp_reg_update(config,32,0);store64(state+8,0);esp32_store32(0x3ff560ac,er_events(channel));return 0;}
    let pin=load64(state+16);esp_gpio_write(pin,(load64(state+32)>>18)&1);esp_gpio_output(pin);
    if load64(state+8){esp32_store32(er_memory(channel),0);esp_reg_update(config,24,24);esp_reg_update(config,24,0);let error=esp_wait_mask(0x3ff560a0,1<<(channel*3),1<<(channel*3),64000000);if error{store64(state+8,3);return error;}}
    store64(state+8,0);esp32_store32(0x3ff560ac,er_events(channel));return 0;
}
fn esp_rmt_write(channel,symbols,count,cycles) {
    if channel<0 || channel>7 || count<1 || count>63 || !esp_buffer_valid(symbols,count*4) || (symbols&3) || cycles<1 || cycles>2147483647{return -22;}
    let state=er_state(channel);if !state || load64(state)!=1{return -19;}let i=0;while i<count{let value=esp32_load32(symbols+i*4);if !(value&32767) || !((value>>16)&32767){return -22;}i=i+1;}
    let ps=esp32_irq_save();let error=er_ready(channel,state);if error{esp32_irq_restore(ps);return error;}store64(state+8,1);esp32_irq_restore(ps);let start=esp32_cycles();let config=er_config(channel)+4;
    esp32_store32(config,load64(state+32)|24);esp32_store32(config,load64(state+32));i=0;while i<count{esp32_store32(er_memory(channel)+i*4,esp32_load32(symbols+i*4));i=i+1;}esp32_store32(er_memory(channel)+count*4,0);esp32_store32(0x3ff560ac,er_events(channel));esp_gpio_write(load64(state+16),(load64(state+32)>>18)&1);esp_gpio_route_output(load64(state+16),87+channel);
    let elapsed=(esp32_cycles()-start)&4294967295;if elapsed>=cycles{store64(state+8,0);return -110;}esp_reg_update(config,1,1);error=0;let done=0;
    while !done && !error{let raw=esp32_load32(0x3ff560a0);if raw&(1<<(channel*3+2)){error= -5;}else if raw&(1<<(channel*3)){done=1;}else if ((esp32_cycles()-start)&4294967295)>=cycles{error= -110;}}
    if error{esp_rmt_stop(channel);return error;}store64(state+8,0);esp32_store32(0x3ff560ac,er_events(channel));return count;
}
fn esp_rmt_rx_start(channel) {
    if channel<0 || channel>7{return -22;}let state=er_state(channel);if !state || load64(state)!=2{return -19;}let ps=esp32_irq_save();if load64(state+8){esp32_irq_restore(ps);return -16;}store64(state+8,1);let config=er_config(channel)+4;
    esp32_store32(config,load64(state+32)&~32);let i=0;while i<load64(state+48)*64{esp32_store32(er_memory(channel)+i*4,0);i=i+1;}esp32_store32(config,load64(state+32)|20);esp32_store32(config,load64(state+32));esp32_store32(0x3ff560ac,er_events(channel));esp_reg_update(config,2,2);esp32_irq_restore(ps);return 0;
}
fn esp_rmt_rx_finish(channel,symbols,capacity,cycles) {
    if channel<0 || channel>7 || capacity<1 || capacity>512 || !esp_buffer_valid(symbols,capacity*4) || (symbols&3) || cycles<1 || cycles>2147483647{return -22;}let state=er_state(channel);if !state || load64(state)!=2 || load64(state+8)!=1{return -19;}if capacity>load64(state+48)*64{return -22;}
    let start=esp32_cycles();let done=0;let error=0;while !done && !error{let raw=esp32_load32(0x3ff560a0);let written=(esp32_load32(0x3ff56060+channel*4)&1023)-channel*64;
        if raw&(1<<(channel*3+2)){error= -75;}else if raw&(1<<(channel*3+1)) || written>=capacity{done=1;}else if ((esp32_cycles()-start)&4294967295)>=cycles{error= -110;}}
    esp_reg_update(er_config(channel)+4,34,0);store64(state+8,0);if error{esp32_store32(0x3ff560ac,er_events(channel));return error;}
    let i=0;let complete=0;while i<capacity && !complete{let value=esp32_load32(er_memory(channel)+i*4);if !(value&32767){complete=1;}else{esp32_store32(symbols+i*4,value);i=i+1;if !((value>>16)&32767){complete=1;}}}esp32_store32(0x3ff560ac,er_events(channel));return i;
}
fn esp_rmt_read(channel,symbols,capacity,cycles){if channel<0 || channel>7 || capacity<1 || capacity>512 || !esp_buffer_valid(symbols,capacity*4) || (symbols&3) || cycles<1 || cycles>2147483647{return -22;}let state=er_state(channel);if !state || load64(state)!=2{return -19;}if capacity>load64(state+48)*64{return -22;}let error=esp_rmt_rx_start(channel);if error{return error;}return esp_rmt_rx_finish(channel,symbols,capacity,cycles);}
fn esp_rmt_deinit(channel) {
    if channel<0 || channel>7{return -22;}let state=er_state(channel);if !state || !load64(state){return 0;}let error=esp_rmt_stop(channel);if error{return error;}let ps=esp32_irq_save();esp_gpio_input(load64(state+16),0);esp32_store32(er_config(channel)+4,0);let c0=0;if !channel{c0=1<<31;}esp32_store32(er_config(channel),c0);er_memory_mask=er_memory_mask&~load64(state+56);store64(state+48,0);store64(state+56,0);store64(state,0);store64(state+8,0);let any=0;let i=0;while i<8{any=any|load64(er_state(i));i=i+1;}if !any{esp_reg_update(0x3ff000c0,1<<9,0);}esp32_irq_restore(ps);return 0;
}
