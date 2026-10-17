import "esp32-common.flex";
// Original ESP32 I2C0/1 master, 80 MHz APB, 7-bit addressing. One transaction
// fits the32-byte FIFOs: write<=30, read<=32, combined via repeated START.
// External pull-ups determine usable bus timing. Native GPIO pulls aid idle.
// Provenance: official ESP-IDF v5.5.1 esp32 i2c_ll.h/i2c_reg.h.
global esp_i2c_states=0;
fn esp_i2c_base(bus) {if bus<0 || bus>1 {return 0;}return 0x3ff53000+bus*81920;}
// ESP32 TX uses the APB FIFO alias, not the DPORT register window.
fn ei_tx_byte(bus,byte) {esp32_store32(0x6001301c+bus*81920,byte);return 0;}
// DPORT RX erratum workaround: mask interrupts and synchronize with a harmless
// APB read immediately before consuming the FIFO word. CPU1 is not started.
fn ei_rx_byte(base) {let ps=esp32_irq_save();esp32_load32(0x3ff40078);let byte=esp32_load32(base+28);esp32_irq_restore(ps);return byte;}
fn ei_state(bus) {if !esp_i2c_base(bus) || !esp_i2c_states {return 0;}return esp_i2c_states+bus*64;}
fn ei_reset(bus,state) {
    let base=esp_i2c_base(bus);let bit=7+bus*11;let ps=esp32_irq_save();esp_clock_enable(0,bit);esp_reg_update(0x3ff000c4,1<<bit,1<<bit);esp_reg_update(0x3ff000c4,1<<bit,0);esp32_irq_restore(ps);
    let half=load64(state+32);esp32_store32(base+4,0x113);esp32_store32(base,half-1);esp32_store32(base+56,half-7);esp32_store32(base+48,half/2);esp32_store32(base+52,half/2);
    esp32_store32(base+64,half);esp32_store32(base+68,half);esp32_store32(base+72,half);esp32_store32(base+76,half);esp32_store32(base+12,half*20);esp32_store32(base+80,0);esp32_store32(base+84,0);
    esp32_store32(base+24,3<<12);esp32_store32(base+24,0);esp32_store32(base+40,0);esp32_store32(base+36,65535);return 0;
}
fn ei_route(bus,state) {let clock=29;let data=30;if bus {clock=95;data=96;}esp_gpio_route_output(load64(state+24),clock);esp_gpio_route_input(load64(state+24),clock);esp_gpio_route_output(load64(state+16),data);esp_gpio_route_input(load64(state+16),data);return 0;}
fn esp_i2c_init(bus,sda,scl,hz) {
    let base=esp_i2c_base(bus);if !base || !esp_gpio_valid(sda) || sda>=34 || !esp_gpio_valid(scl) || scl>=34 || sda==scl || hz<10000 || hz>400000 {return -22;}let ps=esp32_irq_save();
    if !esp_i2c_states {let p=alloc(128);if p<=0 {esp32_irq_restore(ps);return -12;}let i=0;while i<128 {store8(p+i,0);i=i+1;}esp_i2c_states=p;}
    let state=ei_state(bus);if load64(state) || load64(state+8) {esp32_irq_restore(ps);return -16;}store64(state+8,1);esp32_irq_restore(ps);
    store64(state+16,sda);store64(state+24,scl);store64(state+32,(80000000+hz*2-1)/(hz*2));ei_reset(bus,state);
    esp_gpio_write(sda,1);esp_gpio_write(scl,1);esp_gpio_open_drain(sda,1);esp_gpio_open_drain(scl,1);esp_gpio_pull(sda,1);esp_gpio_pull(scl,1);ei_route(bus,state);store64(state,1);store64(state+8,0);return 0;
}
fn esp_i2c_deinit(bus) {
    let base=esp_i2c_base(bus);if !base {return -22;}let state=ei_state(bus);if !state {return 0;}let ps=esp32_irq_save();if load64(state+8) {esp32_irq_restore(ps);return -16;}if !load64(state) {esp32_irq_restore(ps);return 0;}store64(state+8,1);esp32_irq_restore(ps);
    ei_reset(bus,state);let sda=load64(state+16);let scl=load64(state+24);esp_gpio_input(sda,0);esp_gpio_input(scl,0);esp_gpio_open_drain(sda,0);esp_gpio_open_drain(scl,0);
    ps=esp32_irq_save();esp_reg_update(0x3ff000c0,1<<(7+bus*11),0);store64(state,0);store64(state+8,0);esp32_irq_restore(ps);return 0;
}
fn esp_i2c_command(base,index,op,count,ack) {esp32_store32(base+88+index*4,(op<<11)|count|ack);return index+1;}
fn esp_i2c_transfer(bus,address,tx,tx_size,rx,rx_size,cycles) {
    let base=esp_i2c_base(bus);if !base || address<0 || address>127 || tx_size<0 || tx_size>30 || rx_size<0 || rx_size>32 || cycles<1 || cycles>2147483647 {return -22;}
    if (tx_size && !esp_buffer_valid(tx,tx_size)) || (rx_size && !esp_buffer_valid(rx,rx_size)) {return -22;}let state=ei_state(bus);if !state || !load64(state) {return -19;}let ps=esp32_irq_save();if load64(state+8) {esp32_irq_restore(ps);return -16;}store64(state+8,1);esp32_irq_restore(ps);
    if (esp32_load32(base+8)&16) || !esp_gpio_read(load64(state+16)) || !esp_gpio_read(load64(state+24)) {store64(state+8,0);return -16;}
    let start=esp32_cycles();esp32_store32(base+24,3<<12);esp32_store32(base+24,0);esp32_store32(base+36,65535);let i=0;while i<16 {esp_i2c_command(base,i,4,0,0);i=i+1;}
    let cmd=esp_i2c_command(base,0,0,0,0);let read_first=!tx_size && rx_size;ei_tx_byte(bus,(address<<1)|!!read_first);i=0;while i<tx_size {ei_tx_byte(bus,load8(tx+i));i=i+1;}cmd=esp_i2c_command(base,cmd,1,tx_size+1,256);
    if tx_size && rx_size {cmd=esp_i2c_command(base,cmd,0,0,0);ei_tx_byte(bus,(address<<1)|1);cmd=esp_i2c_command(base,cmd,1,1,256);}
    if rx_size>1 {cmd=esp_i2c_command(base,cmd,2,rx_size-1,0);}if rx_size {cmd=esp_i2c_command(base,cmd,2,1,1024);}esp_i2c_command(base,cmd,3,0,0);
    let error=0;let ready=0;if ((esp32_cycles()-start)&4294967295)>=cycles {error= -110;}else {esp_reg_update(base+4,32,32);}
    while !ready && !error {let status=esp32_load32(base+32);if status&1024 {error= -6;}else if status&32 {error= -11;}else if status&256 {error= -110;}else if status&128 {ready=1;}else if ((esp32_cycles()-start)&4294967295)>=cycles {error= -110;}}
    if !error && (((esp32_load32(base+8)>>8)&63)!=rx_size || !(esp32_load32(base+88+cmd*4)&0x80000000)) {error= -5;}
    if !error {i=0;while i<rx_size {store8(rx+i,ei_rx_byte(base));i=i+1;}esp32_store32(base+36,65535);}else {ei_reset(bus,state);}store64(state+8,0);if error {return error;}return tx_size+rx_size;
}
fn ei_high(pin,start,cycles) {while !esp_gpio_read(pin) {if ((esp32_cycles()-start)&4294967295)>=cycles {return -110;}}return 0;}
fn ei_pause(start,cycles) {if ((esp32_cycles()-start)&4294967295)>=cycles {return -110;}esp_delay_cycles(1200);if ((esp32_cycles()-start)&4294967295)>=cycles {return -110;}return 0;}
// Explicit bus-clear operation. Caller owns the bus: never use this to disturb
// a different master. Nine open-drain SCL pulses and STOP respect clock stretch.
fn esp_i2c_recover(bus,cycles) {
    let state=ei_state(bus);if !esp_i2c_base(bus) || cycles<1 || cycles>2147483647 {return -22;}if !state || !load64(state) {return -19;}let ps=esp32_irq_save();if load64(state+8) {esp32_irq_restore(ps);return -16;}store64(state+8,1);esp32_irq_restore(ps);
    ei_reset(bus,state);let sda=load64(state+16);let scl=load64(state+24);let start=esp32_cycles();esp_gpio_write(sda,1);esp_gpio_write(scl,1);esp_gpio_output(sda);esp_gpio_output(scl);let error=ei_high(scl,start,cycles);let pulse=0;
    while pulse<9 && !error && !esp_gpio_read(sda) {esp_gpio_write(scl,0);error=ei_pause(start,cycles);esp_gpio_write(scl,1);if !error {error=ei_high(scl,start,cycles);}if !error {error=ei_pause(start,cycles);}pulse=pulse+1;}
    if !error && !esp_gpio_read(sda) {error= -16;}
    if !error {esp_gpio_write(scl,0);esp_gpio_write(sda,0);error=ei_pause(start,cycles);esp_gpio_write(scl,1);if !error {error=ei_high(scl,start,cycles);}if !error {error=ei_pause(start,cycles);}esp_gpio_write(sda,1);}
    // Always release both lines, including a clock-stretch timeout.
    esp_gpio_write(sda,1);esp_gpio_write(scl,1);ei_route(bus,state);ei_reset(bus,state);store64(state+8,0);return error;
}
