import "esp32-common.flex";
// Original ESP32 GPSPI2/3, 80 MHz APB, MSB-first bytes, modes0..3.
// CPU FIFO transfers; software-controlled CS. SPI0/1 remain flash/PSRAM-owned.
// Register provenance: official ESP-IDF v5.5.1 spi_ll.h/spi_reg.h.
global esp_spi_states=0;
fn esp_spi_base(bus) {if bus<2 || bus>3 {return 0;}return 0x3ff64000+(bus-2)*4096;}
fn es_state(bus) {if !esp_spi_base(bus) || !esp_spi_states {return 0;}return esp_spi_states+(bus-2)*64;}
fn es_reset(bus,state) {
    let base=esp_spi_base(bus);let bit=6;if bus==3 {bit=16;}let ps=esp32_irq_save();esp_clock_enable(0,bit);esp_reg_update(0x3ff000c4,1<<bit,1<<bit);esp_reg_update(0x3ff000c4,1<<bit,0);esp32_irq_restore(ps);
    esp32_store32(base,0);esp32_store32(base+8,0);esp32_store32(base+20,0);esp32_store32(base+24,load64(state+40));esp32_store32(base+28,load64(state+48));esp32_store32(base+32,0);esp32_store32(base+36,0);esp32_store32(base+52,load64(state+56));esp32_store32(base+56,0);return 0;
}
fn esp_spi_init(bus,sck,mosi,miso,hz,mode) {
    let base=esp_spi_base(bus);
    if !base || !esp_gpio_valid(sck) || sck>=34 || (mosi!= -1 && (!esp_gpio_valid(mosi) || mosi>=34)) || (miso!= -1 && !esp_gpio_valid(miso)) || (mosi== -1 && miso== -1) || hz<40000 || hz>20000000 || mode<0 || mode>3 {return -22;}
    if sck==mosi || sck==miso || (mosi>=0 && mosi==miso) {return -22;}let ps=esp32_irq_save();
    if !esp_spi_states {let p=alloc(128);if p<=0 {esp32_irq_restore(ps);return -12;}let i=0;while i<128 {store8(p+i,0);i=i+1;}esp_spi_states=p;}
    let state=es_state(bus);if load64(state) || load64(state+8) {esp32_irq_restore(ps);return -16;}store64(state+8,1);esp32_irq_restore(ps);
    // Round down the resulting clock so it never exceeds the requested rate.
    let pre=(80000000+hz*64-1)/(hz*64);if pre<1 {pre=1;}let n=(80000000+hz*pre-1)/(hz*pre);if n<2 {n=2;}
    let cpol=(mode>>1)&1;store64(state+16,sck);store64(state+24,mosi);store64(state+32,miso);store64(state+40,((pre-1)<<18)|((n-1)<<12)|((n/2-1)<<6)|(n-1));store64(state+48,1|(((mode&1)^cpol)<<7));store64(state+56,7|(cpol<<29));es_reset(bus,state);
    let clock=8;let out=10;let input=9;if bus==3 {clock=63;out=65;input=64;}esp_gpio_route_output(sck,clock);esp_gpio_open_drain(sck,0);
    if mosi>=0 {esp_gpio_route_output(mosi,out);esp_gpio_open_drain(mosi,0);}if miso>=0 {esp_gpio_input(miso,0);esp_gpio_route_input(miso,input);}
    store64(state,1);store64(state+8,0);return 80000000/(pre*n);
}
fn esp_spi_deinit(bus) {
    let base=esp_spi_base(bus);if !base {return -22;}let state=es_state(bus);if !state {return 0;}let ps=esp32_irq_save();if load64(state+8) {esp32_irq_restore(ps);return -16;}if !load64(state) {esp32_irq_restore(ps);return 0;}store64(state+8,1);esp32_irq_restore(ps);
    es_reset(bus,state);esp_gpio_input(load64(state+16),0);if load64(state+24)>=0 {esp_gpio_input(load64(state+24),0);}if load64(state+32)>=0 {esp_gpio_input(load64(state+32),0);}
    let bit=6;if bus==3 {bit=16;}ps=esp32_irq_save();esp_reg_update(0x3ff000c0,1<<bit,0);store64(state,0);store64(state+8,0);esp32_irq_restore(ps);return 0;
}
fn esp_spi_transfer(bus,tx,rx,size,cycles) {
    let base=esp_spi_base(bus);if !base || size<0 || size>65536 || cycles<1 || cycles>2147483647 {return -22;}if !size {return 0;}
    if (!tx && !rx) || (tx && !esp_buffer_valid(tx,size)) || (rx && !esp_buffer_valid(rx,size)) {return -22;}let state=es_state(bus);if !state || !load64(state) {return -19;}
    if (tx && load64(state+24)<0) || (rx && load64(state+32)<0) {return -22;}if tx && rx && tx!=rx && tx<rx+size && rx<tx+size {return -22;}
    let ps=esp32_irq_save();if load64(state+8) {esp32_irq_restore(ps);return -16;}store64(state+8,1);esp32_irq_restore(ps);let start=esp32_cycles();let done=0;let error=0;
    while done<size && !error {
        let count=size-done;if count>64 {count=64;}let word=0;while word<16 {
            let value=0;let byte=0;while byte<4 {let at=word*4+byte;if tx && at<count {value=value|(load8(tx+done+at)<<(byte*8));}byte=byte+1;}esp32_store32(base+128+word*4,value);word=word+1;
        }
        let elapsed=(esp32_cycles()-start)&4294967295;if elapsed>=cycles {error= -110;}else {
            let user=load64(state+48)|(1<<27);if rx {user=user|(1<<28);}esp32_store32(base+28,user);esp32_store32(base+40,count*8-1);esp32_store32(base+44,count*8-1);esp32_store32(base+56,0);esp32_store32(base,1<<18);
            error=esp_wait_mask(base+56,16,16,cycles-elapsed);
            if !error && rx {let i=0;while i<count {store8(rx+done+i,esp32_load32(base+128+(i/4)*4)>>((i&3)*8));i=i+1;}}if !error {done=done+count;}
        }
    }if error {es_reset(bus,state);}store64(state+8,0);if error {return error;}return done;
}
