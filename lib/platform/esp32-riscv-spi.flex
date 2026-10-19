// GPSPI2 master only: SPI0/1 stay flash-owned; neither chip exposes GPSPI3.
// 40MHz XTAL, MSB-first bytes, modes0..3, caller-controlled software CS.
// CPU FIFO path; DMA/slave/queued-IRQ transfers remain separate adapters.
global esp_spi_states=0;
fn esp_spi_base(bus) {if !esp_riscv_ready() || bus!=2 {return 0;}if rv_hal_chip==13 {return 0x60081000;}return 0x60024000;}
fn esr_state(bus) {if !esp_spi_base(bus) {return 0;}return esp_spi_states;}
fn esr_enabled() {if rv_hal_chip==13 {return esp32_load32(0x600960c0)&1;}return esp32_load32(0x600c0010)&64;}
fn esr_busy(base) {
    if rv_hal_chip==13 {if esp32_load32(0x600960c0)&2 {return 1;}}else {if esp32_load32(0x600c0018)&64 {return 1;}}
    return (esp32_load32(base)&((1<<23)|(1<<24))) || esp32_load32(base+0x34) || (esp32_load32(base+0x30)&(3<<27)) || (esp32_load32(base+0xe0)&(3<<26));
}
fn esr_reset(base,state) {
    let ps=esp32_irq_save();
    if rv_hal_chip==13 {esp_reg_update(0x600960c0,3,3);esp_reg_update(0x600960c0,2,0);esp_reg_update(0x600960c4,(3<<20)|(1<<22),1<<22);}
    else {esp_reg_update(0x600c0010,64,64);esp_reg_update(0x600c0018,64,64);esp_reg_update(0x600c0018,64,0);esp_reg_update(base+0xe8,7,3);}
    esp32_store32(base,0);esp32_store32(base+8,0);esp32_store32(base+12,load64(state+40));esp32_store32(base+16,load64(state+48));esp32_store32(base+20,0);esp32_store32(base+24,0);
    esp32_store32(base+32,load64(state+56));esp32_store32(base+48,0);esp32_store32(base+52,0);esp32_store32(base+56,0x1fffff);esp32_store32(base+224,0);
    esp32_irq_restore(ps);return 0;
}
fn esp_spi_init(bus,sck,mosi,miso,hz,mode) {
    if !esp_riscv_ready() {return -95;}let base=esp_spi_base(bus);
    if !base || !esp_gpio_valid(sck) || (mosi!= -1 && !esp_gpio_valid(mosi)) || (miso!= -1 && !esp_gpio_valid(miso)) || (mosi== -1 && miso== -1) || hz<40000 || hz>20000000 || mode<0 || mode>3 {return -22;}
    if sck==mosi || sck==miso || (mosi>=0 && mosi==miso) {return -22;}let ps=esp32_irq_save();
    let state=esr_state(bus);if esp32_load32(esp32_state()+16) || (state && (load64(state)||load64(state+8))) || (esr_enabled() && esr_busy(base)) {esp32_irq_restore(ps);return -16;}
    if !state {state=alloc(96);if state<=0 {esp32_irq_restore(ps);return -12;}esp_spi_states=state;}
    store64(state+8,1);let pre=(40000000+hz*64-1)/(hz*64);let n=(40000000+hz*pre-1)/(hz*pre);if n<2 {n=2;}
    let cpol=(mode>>1)&1;store64(state+16,sck);store64(state+24,mosi);store64(state+32,miso);store64(state+40,((pre-1)<<18)|((n-1)<<12)|((n/2-1)<<6)|(n-1));
    store64(state+48,1|(((mode&1)^cpol)<<9));store64(state+56,63|(cpol<<29));store64(state+64,0);store64(state+72,0);esr_reset(base,state);
    esp_gpio_write(sck,cpol);esp_gpio_route_output(sck,63);esp_gpio_open_drain(sck,0);
    if mosi>=0 {esp_gpio_write(mosi,0);esp_gpio_route_output(mosi,65);esp_gpio_open_drain(mosi,0);}if miso>=0 {esp_gpio_input(miso,0);esp_gpio_open_drain(miso,0);esp_gpio_route_input(miso,64);}
    store64(state,1);store64(state+8,0);esp32_irq_restore(ps);return 40000000/(pre*n);
}
fn esp_spi_deinit(bus) {
    if !esp_riscv_ready() {return -95;}let base=esp_spi_base(bus);if !base {return -22;}let state=esr_state(bus);if !state {return 0;}let ps=esp32_irq_save();
    if esp32_load32(esp32_state()+16) || load64(state+8) || (load64(state) && esr_busy(base)) {esp32_irq_restore(ps);return -16;}if !load64(state) {esp32_irq_restore(ps);return 0;}
    store64(state+8,1);esr_reset(base,state);esp_gpio_input(load64(state+16),0);if load64(state+24)>=0 {esp_gpio_input(load64(state+24),0);}if load64(state+32)>=0 {esp_gpio_input(load64(state+32),0);}
    if rv_hal_chip==13 {esp_reg_update(0x600960c4,1<<22,0);esp_reg_update(0x600960c0,1,0);}else {esp_reg_update(base+0xe8,3,0);esp_reg_update(0x600c0010,64,0);}
    store64(state,0);store64(state+8,0);store64(state+64,0);store64(state+72,0);esp32_irq_restore(ps);return 0;
}
fn esr_wait(base,start,cycles,phase) {
    while 1 {
        let command=esp32_load32(base);let status=esp32_load32(base+0x3c);if status&((3<<17)|3) {return -5;}let ready=!(command&(1<<23));
        if phase {ready=(status&(1<<12)) && !(command&(1<<24));}
        if ((esp32_cycles()-start)&4294967295)>=cycles {return -110;}if ready {return 0;}
    }return 0;
}
fn esp_spi_transfer(bus,tx,rx,size,cycles) {
    if !esp_riscv_ready() {return -95;}let base=esp_spi_base(bus);if !base || size<0 || size>65536 || cycles<1 || cycles>2147483647 {return -22;}
    if !size {return 0;}if (!tx && !rx) || (tx && !esp_buffer_valid(tx,size)) || (rx && !esp_buffer_valid(rx,size)) {return -22;}
    if tx && rx && tx!=rx && tx<rx+size && rx<tx+size {return -22;}let state=esr_state(bus);if !state || !load64(state) {return -19;}
    if (tx && load64(state+24)<0) || (rx && load64(state+32)<0) {return -22;}
    let ps=esp32_irq_save();if esp32_load32(esp32_state()+16) || load64(state+8) || esr_busy(base) {esp32_irq_restore(ps);return -16;}
    store64(state+8,1);store64(state+64,0);store64(state+72,0);esp32_irq_restore(ps);let start=esp32_cycles();let done=0;let error=0;
    while done<size && !error {
        let count=size-done;if count>64 {count=64;}let word=0;
        while word<16 {let value=0;let byte=0;while byte<4 {let at=word*4+byte;if tx && at<count {value=value|(load8(tx+done+at)<<(byte*8));}byte=byte+1;}esp32_store32(base+152+word*4,value);word=word+1;}
        if ((esp32_cycles()-start)&4294967295)>=cycles {error= -110;}
        else {
            let user=load64(state+48)|(1<<27);if rx {user=user|(1<<28);}esp32_store32(base+16,user);esp32_store32(base+28,count*8-1);esp32_store32(base+56,1<<12);esp32_store32(base,1<<23);
            error=esr_wait(base,start,cycles,0);
            if !error {esp32_store32(base,1<<24);error=esr_wait(base,start,cycles,1);}
            if !error {if rx {let i=0;while i<count {store8(rx+done+i,esp32_load32(base+152+(i/4)*4)>>((i&3)*8));i=i+1;}}done=done+count;store64(state+64,done);esp32_store32(base+56,1<<12);}
        }
    }
    if error {esr_reset(base,state);}ps=esp32_irq_save();store64(state+72,error);store64(state+8,0);esp32_irq_restore(ps);if error {return error;}return done;
}
// A failed multi-chunk transaction can retain a completed RX prefix. These
// accessors report that prefix/error; an incomplete chunk is never copied.
fn esp_spi_transferred(bus) {if !esp_riscv_ready() {return -95;}if !esp_spi_base(bus) {return -22;}let state=esr_state(bus);if !state || !load64(state) {return -19;}return load64(state+64);}
fn esp_spi_status(bus) {if !esp_riscv_ready() {return -95;}if !esp_spi_base(bus) {return -22;}let state=esr_state(bus);if !state || !load64(state) {return -19;}return load64(state+72);}
