import "esp32s3-common.flex";
// GPSPI2/3 master, 8-bit full duplex, modes 0..3, software-controlled CS.
// SPI0/1 are deliberately excluded: they belong to flash/PSRAM.
fn esp_spi_base(bus) {if bus<2 || bus>3 {return 0;}return 0x60024000+(bus-2)*4096;}
fn esp_spi_init(bus,sck,mosi,miso,hz,mode) {
    let base=esp_spi_base(bus);
    if !base || !esp_gpio_valid(sck) || (mosi!= -1 && !esp_gpio_valid(mosi)) || (miso!= -1 && !esp_gpio_valid(miso)) || hz<40000 || hz>20000000 || mode<0 || mode>3 {return -22;}
    if sck==mosi || sck==miso || (mosi>=0 && mosi==miso) {return -22;}
    esp_clock_enable(0,6+(bus-2)*10);esp32_store32(base+232,3); // XTAL, master clock active
    let pre=(40000000+hz*64-1)/(hz*64);if pre<1 {pre=1;}
    let n=(40000000+hz*pre-1)/(hz*pre);if n<2 {n=2;}
    esp32_store32(base+12,((pre-1)<<18)|((n-1)<<12)|((n/2-1)<<6)|(n-1));
    let cpol=(mode>>1)&1;let user=1|(((mode&1)^cpol)<<9);
    if mosi>=0 {user=user|(1<<27);}if miso>=0 {user=user|(1<<28);}
    esp32_store32(base+8,0);esp32_store32(base+16,user);esp32_store32(base+20,0);esp32_store32(base+24,0);
    esp32_store32(base+32,63|(cpol<<29));esp32_store32(base+48,0);esp32_store32(base+224,0);
    let clk_signal=101;let tx_signal=103;let rx_signal=102;if bus==3 {clk_signal=66;tx_signal=68;rx_signal=67;}
    esp_gpio_route_output(sck,clk_signal);if mosi>=0 {esp_gpio_route_output(mosi,tx_signal);}if miso>=0 {esp_gpio_input(miso,0);esp_gpio_route_input(miso,rx_signal);}
    return 40000000/(pre*n);
}
fn esp_spi_transfer(bus,tx,rx,size,cycles) {
    let base=esp_spi_base(bus);if !base || size<0 || size>65536 || cycles<1 || cycles>2147483647 {return -22;}
    if !size {return 0;}if (!tx && !rx) || (tx && !esp_buffer_valid(tx,size)) || (rx && !esp_buffer_valid(rx,size)) {return -22;}
    let done=0;while done<size {
        let count=size-done;if count>64 {count=64;}
        let word=0;while word<16 {
            let value=0;let byte=0;while byte<4 {let at=word*4+byte;if tx && at<count {value=value|(load8(tx+done+at)<<(byte*8));}byte=byte+1;}
            esp32_store32(base+152+word*4,value);word=word+1;
        }
        esp32_store32(base+28,count*8-1);esp32_store32(base,1<<23);
        let error=esp_wait_mask(base,1<<23,0,cycles);if error {return error;}
        esp32_store32(base,1<<24);error=esp_wait_mask(base,1<<24,0,cycles);if error {return error;}
        if rx {let i=0;while i<count {let value=esp32_load32(base+152+(i/4)*4);store8(rx+done+i,value>>((i&3)*8));i=i+1;}}
        done=done+count;
    }return done;
}
