// HP I2C0 master. C6 LP I2C is a different peripheral and is not selected here.
// Fixed40MHz XTAL; pinned v5.5.1 timing calibration,7-bit addresses and CPU FIFO.
// Write<=31, read<=32; combined write<=30 leaves room for two address bytes.
// External pull-ups determine electrical timing. Recovery is explicitly opt-in.
global esp_i2c_states=0;
fn esp_i2c_base(bus) {if !esp_riscv_ready() || bus!=0 {return 0;}if rv_hal_chip==13 {return 0x60004000;}return 0x60013000;}
fn eir_state(bus) {if !esp_i2c_base(bus) {return 0;}return esp_i2c_states;}
fn eir_mask() {if rv_hal_chip==13 {return 0x7ffff;}return 0x3ffff;}
fn eir_enabled() {if rv_hal_chip==13 {return esp32_load32(0x60096020)&1;}return esp32_load32(0x600c0010)&128;}
fn eir_busy(base) {
    if rv_hal_chip==13 {if esp32_load32(0x60096020)&2 {return 1;}}else {if esp32_load32(0x600c0018)&128 {return 1;}}
    return esp32_load32(base+40) || (esp32_load32(base+4)&((1<<5)|(1<<10))) || (esp32_load32(base+8)&(16|(63<<8)|(63<<18)));
}
fn eir_control() {let control=(1<<4)|(1<<8)|(1<<9);if rv_hal_chip==5 {control=control|3;}return control;}
fn eir_signal() {if rv_hal_chip==13 {return 45;}return 53;}
fn eir_route(state) {let signal=eir_signal();let sda=load64(state+16);let scl=load64(state+24);esp_gpio_route_output(scl,signal);esp_gpio_route_input(scl,signal);esp_gpio_route_output(sda,signal+1);esp_gpio_route_input(sda,signal+1);return 0;}
fn eir_reset(base,state) {
    let ps=esp32_irq_save();let pre=load64(state+32);let half=load64(state+40);let wait=load64(state+48);
    if rv_hal_chip==13 {esp_reg_update(0x60096020,3,3);esp_reg_update(0x60096020,2,0);esp_reg_update(0x60096024,0x5fffff,(pre-1)|(1<<22));}
    else {esp_reg_update(0x600c0010,128,128);esp_reg_update(0x600c0018,128,128);esp_reg_update(0x600c0018,128,0);esp32_store32(base+84,(pre-1)|(1<<21));}
    esp32_store32(base+4,eir_control());esp32_store32(base,half-1);esp32_store32(base+56,(half-wait)|(wait<<9));
    esp32_store32(base+48,half/4-1);esp32_store32(base+52,half/2-1);esp32_store32(base+64,half-1);esp32_store32(base+68,half-1);esp32_store32(base+72,half-1);esp32_store32(base+76,half-1);
    esp32_store32(base+12,load64(state+56)|32);esp32_store32(base+80,0x377);esp32_store32(base+24,0x708b);esp32_store32(base+24,0x408b);esp32_store32(base+40,0);esp32_store32(base+36,eir_mask());
    esp32_store32(base+4,eir_control()|(1<<11));esp32_irq_restore(ps);return 0;
}
fn esp_i2c_init(bus,sda,scl,hz) {
    if !esp_riscv_ready() {return -95;}let base=esp_i2c_base(bus);if !base || !esp_gpio_valid(sda) || !esp_gpio_valid(scl) || sda==scl || hz<10000 || hz>400000 {return -22;}
    let ps=esp32_irq_save();let state=eir_state(bus);if esp32_load32(esp32_state()+16) || (state && (load64(state)||load64(state+8))) || (eir_enabled() && eir_busy(base)) {esp32_irq_restore(ps);return -16;}
    if !state {state=alloc(96);if state<=0 {esp32_irq_restore(ps);return -12;}esp_i2c_states=state;}store64(state+8,1);
    let pre=40000000/(hz*1024)+1;let half=40000000/pre/hz/2;let wait=half/4;if hz>=80000 {wait=half/2-2;}
    let timeout=0;let n=5*half;while n {n=n>>1;timeout=timeout+1;}timeout=timeout+2;
    store64(state+16,sda);store64(state+24,scl);store64(state+32,pre);store64(state+40,half);store64(state+48,wait);store64(state+56,timeout);store64(state+64,0);store64(state+72,0);eir_reset(base,state);
    esp_gpio_open_drain(sda,1);esp_gpio_open_drain(scl,1);esp_gpio_write(sda,1);esp_gpio_write(scl,1);esp_gpio_pull(sda,1);esp_gpio_pull(scl,1);eir_route(state);
    store64(state,1);store64(state+8,0);esp32_irq_restore(ps);return 0;
}
fn esp_i2c_deinit(bus) {
    if !esp_riscv_ready() {return -95;}let base=esp_i2c_base(bus);if !base {return -22;}let state=eir_state(bus);if !state {return 0;}let ps=esp32_irq_save();
    if esp32_load32(esp32_state()+16) || load64(state+8) || (load64(state) && eir_busy(base)) {esp32_irq_restore(ps);return -16;}if !load64(state) {esp32_irq_restore(ps);return 0;}
    store64(state+8,1);eir_reset(base,state);let sda=load64(state+16);let scl=load64(state+24);esp_gpio_write(sda,1);esp_gpio_write(scl,1);esp_gpio_input(sda,0);esp_gpio_input(scl,0);esp_gpio_open_drain(sda,0);esp_gpio_open_drain(scl,0);
    if rv_hal_chip==13 {esp_reg_update(0x60096024,1<<22,0);esp_reg_update(0x60096020,1,0);}else {esp_reg_update(base+84,1<<21,0);esp_reg_update(0x600c0010,128,0);}
    store64(state,0);store64(state+8,0);store64(state+64,0);store64(state+72,0);esp32_irq_restore(ps);return 0;
}
fn esp_i2c_command(base,index,op,count,ack) {esp32_store32(base+88+index*4,(op<<11)|count|ack);return index+1;}
fn eir_finish(base,state,error,count) {
    if error {eir_reset(base,state);}else {esp32_store32(base+36,eir_mask());}let ps=esp32_irq_save();store64(state+64,error);store64(state+72,count);store64(state+8,0);esp32_irq_restore(ps);return error;
}
fn esp_i2c_transfer(bus,address,tx,tx_size,rx,rx_size,cycles) {
    if !esp_riscv_ready() {return -95;}let base=esp_i2c_base(bus);
    if !base || address<0 || address>127 || tx_size<0 || tx_size>31 || rx_size<0 || rx_size>32 || (rx_size && tx_size>30) || cycles<1 || cycles>2147483647 {return -22;}
    if (tx_size && !esp_buffer_valid(tx,tx_size)) || (rx_size && !esp_buffer_valid(rx,rx_size)) {return -22;}let state=eir_state(bus);if !state || !load64(state) {return -19;}let ps=esp32_irq_save();
    if esp32_load32(esp32_state()+16) || load64(state+8) || eir_busy(base) || !esp_gpio_read(load64(state+16)) || !esp_gpio_read(load64(state+24)) {esp32_irq_restore(ps);return -16;}
    store64(state+8,1);store64(state+64,0);store64(state+72,0);esp32_irq_restore(ps);let start=esp32_cycles();
    esp_reg_update(base+24,3<<12,3<<12);esp_reg_update(base+24,3<<12,0);esp32_store32(base+36,eir_mask());let i=0;while i<8 {esp_i2c_command(base,i,4,0,0);i=i+1;}
    let cmd=esp_i2c_command(base,0,6,0,0);let read_first=!tx_size && rx_size;esp32_store32(base+28,(address<<1)|!!read_first);i=0;while i<tx_size {esp32_store32(base+28,load8(tx+i));i=i+1;}cmd=esp_i2c_command(base,cmd,1,tx_size+1,256);
    if tx_size && rx_size {cmd=esp_i2c_command(base,cmd,6,0,0);esp32_store32(base+28,(address<<1)|1);cmd=esp_i2c_command(base,cmd,1,1,256);}
    if rx_size>1 {cmd=esp_i2c_command(base,cmd,3,rx_size-1,0);}if rx_size {cmd=esp_i2c_command(base,cmd,3,1,1024);}esp_i2c_command(base,cmd,2,0,0);
    let error=0;let ready=0;esp_reg_update(base+4,1<<11,1<<11);if ((esp32_cycles()-start)&4294967295)>=cycles {error= -110;}else {esp_reg_update(base+4,1<<5,1<<5);}
    while !error && !ready {
        let status=esp32_load32(base+32);
        if status&(1<<5) {error= -11;}else if status&(1<<10) {error= -6;}else if status&((1<<8)|(3<<13)) {error= -110;}else if status&((1<<2)|(1<<11)) {error= -5;}
        else if status&(1<<7) {ready=1;}
        if ((esp32_cycles()-start)&4294967295)>=cycles && !error {error= -110;}
    }
    if !error {
        if ((esp32_load32(base+8)>>8)&63)!=rx_size {error= -5;}i=0;while i<=cmd && !error {if !(esp32_load32(base+88+i*4)&0x80000000) {error= -5;}i=i+1;}
    }
    if !error {i=0;while i<rx_size {store8(rx+i,esp32_load32(base+28));i=i+1;}}
    let count=0;if !error {count=tx_size+rx_size;}eir_finish(base,state,error,count);if error {return error;}return count;
}
fn esp_i2c_probe(bus,address,cycles) {return esp_i2c_transfer(bus,address,0,0,0,0,cycles);}
fn esp_i2c_status(bus) {if !esp_riscv_ready() {return -95;}if !esp_i2c_base(bus) {return -22;}let state=eir_state(bus);if !state || !load64(state) {return -19;}return load64(state+64);}
fn esp_i2c_transferred(bus) {if !esp_riscv_ready() {return -95;}if !esp_i2c_base(bus) {return -22;}let state=eir_state(bus);if !state || !load64(state) {return -19;}return load64(state+72);}
fn eir_high(pin,start,cycles) {while !esp_gpio_read(pin) {if ((esp32_cycles()-start)&4294967295)>=cycles {return -110;}}return 0;}
// At the documented 160MHz CPU ceiling,8000 cycles allow at least50us per
// recovery half-period, keeping bus-clear clocks within the 10kHz init floor.
fn eir_pause(start,cycles) {let elapsed=(esp32_cycles()-start)&4294967295;if elapsed>=cycles || cycles-elapsed<8000 {return -110;}esp_delay_cycles(8000);if ((esp32_cycles()-start)&4294967295)>=cycles {return -110;}return 0;}
// Caller owns the bus: never invoke this to disturb a different active master.
// Nine released/open-drain SCL pulses and STOP respect clock stretch and one
// cycle budget. Both lines are released and matrix routes restored on every exit.
fn esp_i2c_recover(bus,cycles) {
    if !esp_riscv_ready() {return -95;}let base=esp_i2c_base(bus);if !base || cycles<1 || cycles>2147483647 {return -22;}let state=eir_state(bus);if !state || !load64(state) {return -19;}let ps=esp32_irq_save();
    if esp32_load32(esp32_state()+16) || load64(state+8) || esp32_load32(base+40) {esp32_irq_restore(ps);return -16;}store64(state+8,1);store64(state+64,0);store64(state+72,0);esp32_irq_restore(ps);
    let start=esp32_cycles();eir_reset(base,state);let sda=load64(state+16);let scl=load64(state+24);esp_gpio_open_drain(sda,1);esp_gpio_open_drain(scl,1);esp_gpio_pull(sda,1);esp_gpio_pull(scl,1);esp_gpio_write(sda,1);esp_gpio_write(scl,1);esp_gpio_output(sda);esp_gpio_output(scl);let error=eir_high(scl,start,cycles);let pulse=0;
    while pulse<9 && !error && !esp_gpio_read(sda) {esp_gpio_write(scl,0);error=eir_pause(start,cycles);esp_gpio_write(scl,1);if !error {error=eir_high(scl,start,cycles);}if !error {error=eir_pause(start,cycles);}pulse=pulse+1;}
    if !error && !esp_gpio_read(sda) {error= -16;}
    if !error {esp_gpio_write(scl,0);esp_gpio_write(sda,0);error=eir_pause(start,cycles);esp_gpio_write(scl,1);if !error {error=eir_high(scl,start,cycles);}if !error {error=eir_pause(start,cycles);}esp_gpio_write(sda,1);}
    esp_gpio_write(sda,1);esp_gpio_write(scl,1);ps=esp32_irq_save();eir_route(state);eir_reset(base,state);store64(state+64,error);store64(state+8,0);esp32_irq_restore(ps);return error;
}
