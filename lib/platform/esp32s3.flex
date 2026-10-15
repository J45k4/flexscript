// ESP32-S3 bare-metal adapter for --target esp32s3 only.
// Register provenance: Espressif ESP-IDF components/soc/esp32s3/register/soc/
// uart_reg.h, gpio_reg.h and io_mux_reg.h (Apache-2.0 OR MIT).
// UART0 retains the ROM's clock/baud and TXD=GPIO43, RXD=GPIO44 routing.
fn esp_uart_putc(byte) {
    while ((esp32_load32(0x6000001c)>>16)&1023)>=126 {}
    esp32_store32(0x60000000,byte);return 0;
}
fn esp_uart_write(text) {let i=0;while load8(text+i) {esp_uart_putc(load8(text+i));i=i+1;}return i;}
fn esp_uart_hex(value) {
    let alphabet="0123456789abcdef";let shift=60;
    while shift>=0 {esp_uart_putc(load8(alphabet+((value>>shift)&15)));shift=shift-4;}return 0;
}
fn esp_uart_flush() {while ((esp32_load32(0x6000001c)>>16)&1023) {}return 0;}
fn esp_uart_read() {if !(esp32_load32(0x6000001c)&1023) {return -1;}return esp32_load32(0x60000000)&255;}
// All physical S3 pads; module-reserved flash/PSRAM pins remain board-specific.
fn esp_gpio_valid(pin) {return pin>=0 && pin<=48 && (pin<22 || pin>=26);}
fn esp_gpio_mux(pin) {
    if !esp_gpio_valid(pin) {return -22;}if pin<=21 {let rtc=0x60008484+pin*4;esp32_store32(rtc,esp32_load32(rtc)&~(1<<19));}let mux=0x60009004+pin*4;
    esp32_store32(mux,(esp32_load32(mux)&~0x7000)|0x1000|0x200);return 0;
}
fn esp_gpio_output(pin) {
    if !esp_gpio_valid(pin) {return -22;}esp_gpio_mux(pin);esp32_store32(0x60004554+pin*4,256|1024);
    let address=0x60004024;if pin>=32 {address=0x60004030;}esp32_store32(address,1<<(pin&31));return 0;
}
fn esp_gpio_write(pin,high) {
    if !esp_gpio_valid(pin) {return -22;}let address=0x6000400c;if high {address=0x60004008;}if pin>=32 {address=address+12;}
    esp32_store32(address,1<<(pin&31));return 0;
}
fn esp_gpio_input(pin,pull) {
    if !esp_gpio_valid(pin) || pull<0 || pull>2 {return -22;}esp_gpio_mux(pin);
    let off=0x60004028;if pin>=32 {off=0x60004034;}esp32_store32(off,1<<(pin&31));return esp_gpio_pull(pin,pull);
}
fn esp_gpio_pull(pin,pull) {
    if !esp_gpio_valid(pin) || pull<0 || pull>2 {return -22;}let address=0x60009004+pin*4;let mask=0;if pull==1 {mask=256;}else if pull==2 {mask=128;}
    esp32_store32(address,(esp32_load32(address)&~384)|mask);return 0;
}
fn esp_gpio_read(pin) {if !esp_gpio_valid(pin) {return -22;}let address=0x6000403c;if pin>=32 {address=address+4;}return (esp32_load32(address)>>(pin&31))&1;}
fn esp_gpio_open_drain(pin,enable) {
    if !esp_gpio_valid(pin) {return -22;}let address=0x60004074+pin*4;let bit=0;if enable {bit=4;}esp32_store32(address,(esp32_load32(address)&~4)|bit);return 0;
}
fn esp_gpio_route_output(pin,signal) {if !esp_gpio_valid(pin) || signal<0 || signal>256 {return -22;}esp_gpio_output(pin);esp32_store32(0x60004554+pin*4,signal|1024);return 0;}
fn esp_gpio_route_input(pin,signal) {if !esp_gpio_valid(pin) || signal<0 || signal>255 {return -22;}esp_gpio_mux(pin);esp32_store32(0x60004154+signal*4,pin|128);return 0;}
fn esp_gpio_interrupt(pin,event) {
    if !esp_gpio_valid(pin) || event<0 || event>5 {return -22;}let addr=0x60004074+pin*4;let enable=0;if event {enable=1<<13;}
    esp32_store32(addr,(esp32_load32(addr)&~((31<<13)|(7<<7)))|enable|(event<<7));return 0;
}
fn esp_gpio_pending() {return esp32_load32(0x60004044)|(esp32_load32(0x60004050)<<32);}
fn esp_gpio_ack(mask) {esp32_store32(0x6000404c,mask);esp32_store32(0x60004058,mask>>32);return 0;}
fn esp_delay_cycles(cycles) {
    if cycles<0 || cycles>2147483647 {return -1;}
    let start=esp32_cycles();while ((esp32_cycles()-start)&4294967295)<cycles {}return 0;
}
