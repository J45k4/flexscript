// Original ESP32 LX6 adapter for --target esp32 only.
// Register provenance: Espressif ESP-IDF components/soc/esp32/register/soc/
// uart_reg.h, gpio_reg.h and io_mux_reg.h (Apache-2.0 OR MIT).
// UART0 retains the ROM's clock/baud and TXD=GPIO1, RXD=GPIO3 routing.
fn esp_uart_putc(byte) {
    while ((esp32_load32(0x3ff4001c)>>16)&255)>=126 {}
    esp32_store32(0x3ff40000,byte);return 0;
}
fn esp_uart_write(text) {let i=0;while load8(text+i) {esp_uart_putc(load8(text+i));i=i+1;}return i;}
fn esp_uart_hex(value) {
    let alphabet="0123456789abcdef";let shift=60;
    while shift>=0 {esp_uart_putc(load8(alphabet+((value>>shift)&15)));shift=shift-4;}return 0;
}
fn esp_uart_flush() {while ((esp32_load32(0x3ff4001c)>>16)&4095) {}return 0;}
// UART_STATUS FIFO counts are 8 bits; adjacent bits contain the RX/TX state.
// CPU erratum 3.21: an interrupt during FIFO read can stall the APB bridge.
fn esp_uart_read() {let ps=esp32_irq_save();let byte= -1;if esp32_load32(0x3ff4001c)&255 {byte=esp32_load32(0x3ff40000)&255;}esp32_irq_restore(ps);return byte;}
// Original ESP32 pads. GPIO34..39 are input only and have no internal pulls.
// GPIO6..11 are normally used by module flash; GPIO16/17 may be PSRAM.
fn esp_gpio_valid(pin) {return pin>=0 && pin<=39 && pin!=20 && pin!=24 && (pin<28 || pin>31);}
fn esp_gpio_mux_address(pin) {
    if !esp_gpio_valid(pin) {return -22;}
    // Nonlinear classic ESP32 IO_MUX table, from ESP-IDF v5.5.1 gpio_periph.c.
    let offsets="44884084486c60646854585c3438303c4c507074787c808cff24282cffffffff1c20141804080c10";
    let a=load8(offsets+pin*2)-48;let b=load8(offsets+pin*2+1)-48;if a>9 {a=a-39;}if b>9 {b=b-39;}
    return 0x3ff49000+(a<<4)+b;
}
fn esp_gpio_hex(text,offset) {let a=load8(text+offset)-48;let b=load8(text+offset+1)-48;if a>9 {a=a-39;}if b>9 {b=b-39;}return (a<<4)|b;}
fn esp_gpio_mux(pin) {
    let mux=esp_gpio_mux_address(pin);if mux<0 {return mux;}
    let pads="981300009c13000094130000000000000000000000000000a813a413ac13a01300000000000000000000000000000000000084118811b01300000000000000008c118c12801d801c7c1b7c1a7c197c18";let reg=esp_gpio_hex(pads,pin*4);
    if reg {let address=0x3ff48400+reg;let mask=1<<esp_gpio_hex(pads,pin*4+2);esp32_store32(address,esp32_load32(address)&~mask);}
    esp32_store32(mux,(esp32_load32(mux)&~0x7000)|0x2000|0x200);return 0;
}
fn esp_gpio_output(pin) {
    if !esp_gpio_valid(pin) || pin>=34 {return -22;}esp_gpio_mux(pin);esp32_store32(0x3ff44530+pin*4,256|1024);
    let address=0x3ff44024;if pin>=32 {address=0x3ff44030;}esp32_store32(address,1<<(pin&31));return 0;
}
fn esp_gpio_write(pin,high) {
    if !esp_gpio_valid(pin) || pin>=34 {return -22;}let address=0x3ff4400c;if high {address=0x3ff44008;}if pin>=32 {address=address+12;}
    esp32_store32(address,1<<(pin&31));return 0;
}
fn esp_gpio_input(pin,pull) {
    if !esp_gpio_valid(pin) || pull<0 || pull>2 {return -22;}esp_gpio_mux(pin);
    let off=0x3ff44028;if pin>=32 {off=0x3ff44034;}esp32_store32(off,1<<(pin&31));return esp_gpio_pull(pin,pull);
}
fn esp_gpio_pull(pin,pull) {
    if !esp_gpio_valid(pin) || pull<0 || pull>2 {return -22;}if pin>=34 && pull {return -22;}let address=esp_gpio_mux_address(pin);let mask=0;if pull==1 {mask=256;}else if pull==2 {mask=128;}
    esp32_store32(address,(esp32_load32(address)&~384)|mask);return 0;
}
fn esp_gpio_read(pin) {if !esp_gpio_valid(pin) {return -22;}let address=0x3ff4403c;if pin>=32 {address=address+4;}return (esp32_load32(address)>>(pin&31))&1;}
fn esp_gpio_open_drain(pin,enable) {
    if !esp_gpio_valid(pin) || pin>=34 {return -22;}let address=0x3ff44088+pin*4;let bit=0;if enable {bit=4;}esp32_store32(address,(esp32_load32(address)&~4)|bit);return 0;
}
fn esp_gpio_route_output(pin,signal) {if !esp_gpio_valid(pin) || pin>=34 || signal<0 || signal>256 {return -22;}esp_gpio_output(pin);esp32_store32(0x3ff44530+pin*4,signal|1024);return 0;}
fn esp_gpio_route_input(pin,signal) {if !esp_gpio_valid(pin) || signal<0 || signal>255 {return -22;}esp_gpio_mux(pin);esp32_store32(0x3ff44130+signal*4,pin|128);return 0;}
fn esp_gpio_interrupt(pin,event) {
    if !esp_gpio_valid(pin) || event<0 || event>5 {return -22;}let addr=0x3ff44088+pin*4;let enable=0;if event {enable=1<<15;}
    esp32_store32(addr,(esp32_load32(addr)&~((31<<13)|(7<<7)))|enable|(event<<7));return 0;
}
fn esp_gpio_pending() {return esp32_load32(0x3ff44044)|(esp32_load32(0x3ff44050)<<32);}
fn esp_gpio_ack(mask) {esp32_store32(0x3ff4404c,mask);esp32_store32(0x3ff44058,mask>>32);return 0;}
fn esp_delay_cycles(cycles) {
    if cycles<0 || cycles>2147483647 {return -1;}
    let start=esp32_cycles();while ((esp32_cycles()-start)&4294967295)<cycles {}return 0;
}
