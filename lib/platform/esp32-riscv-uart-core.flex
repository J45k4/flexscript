fn esp_uart_bus_base(bus) {if !esp_riscv_ready() {return -95;}if bus<0 || bus>1 {return -22;}let stride=65536;if rv_hal_chip==13 {stride=4096;}return 0x60000000+bus*stride;}
// Both HP UARTs share FIFO/IRQ policy; chip modules supply the peripheral profile.
// Single-byte transfers mask CPU interrupts against concurrent ISR consumption.
fn esp_uart_bus_try_read(bus) {
    let base=esp_uart_bus_base(bus);if base<0 {return base;}let ps=esp32_irq_save();let value= -1;
    if esp32_load32(base+0x1c)&rv_hal_uart_mask {value=esp32_load32(base+0x00)&255;}esp32_irq_restore(ps);return value;
}
fn esp_uart_bus_try_putc(bus,byte) {
    let base=esp_uart_bus_base(bus);if base<0 {return base;}if byte<0 || byte>255 {return -22;}let ps=esp32_irq_save();let result= -11;
    if ((esp32_load32(base+0x1c)>>16)&rv_hal_uart_mask)<128 {esp32_store32(base+0x00,byte);result=0;}esp32_irq_restore(ps);return result;
}
fn esp_uart_bus_irq_source(bus) {let base=esp_uart_bus_base(bus);if base<0 {return base;}if rv_hal_chip==13 {return 43+bus;}return 21+bus;}
fn esp_uart_bus_irq_mask(bus,mask) {let base=esp_uart_bus_base(bus);if base<0 {return base;}if mask<0 || (mask&~0x7ffff) {return -22;}esp32_store32(base+0x0c,mask);return 0;}
fn esp_uart_bus_irq_pending(bus) {let base=esp_uart_bus_base(bus);if base<0 {return base;}return esp32_load32(base+0x08)&0x7ffff;}
fn esp_uart_bus_irq_raw(bus) {let base=esp_uart_bus_base(bus);if base<0 {return base;}return esp32_load32(base+0x04)&0x7ffff;}
fn esp_uart_bus_irq_ack(bus,mask) {let base=esp_uart_bus_base(bus);if base<0 {return base;}if mask<0 || (mask&~0x7ffff) {return -22;}esp32_store32(base+0x10,mask);return 0;}
fn esp_uart_bus_update(bus) {
    let base=esp_uart_bus_base(bus);if base<0 {return base;}let address=base+0x80;let bit=1<<31;
    if rv_hal_chip==13 {address=base+0x98;bit=1;}
    else if esp32_load32(address)&(1<<30) {return 0;}
    if rv_hal_chip==13 {esp32_store32(address,1);}else {esp_reg_update(address,bit,bit);}return esp_wait_mask(address,bit,0,1000000);
}
fn esp_uart_bus_irq_thresholds(bus,rx_full,tx_empty) {
    let base=esp_uart_bus_base(bus);if base<0 {return base;}if rx_full<1 || rx_full>127 || tx_empty<0 || tx_empty>127 {return -22;}let ps=esp32_irq_save();let mask=0x3ffff;let value=rx_full|(tx_empty<<9);
    if rv_hal_chip==13 {mask=0xffff;value=rx_full|(tx_empty<<8);}esp_reg_update(base+0x24,mask,value);let result=esp_uart_bus_update(bus);esp32_irq_restore(ps);return result;
}
// Timeout is expressed in UART bit periods; zero disables it.
fn esp_uart_bus_irq_timeout(bus,bits) {
    let base=esp_uart_bus_base(bus);if base<0 {return base;}if bits<0 || bits>1023 {return -22;}let ps=esp32_irq_save();
    if rv_hal_chip==13 {let value=0;if bits {value=(bits<<2)|1;}esp_reg_update(base+0x64,0xffd,value);}
    else {if bits {esp_reg_update(base+0x60,1023<<16,bits<<16);}let enable=0;if bits {enable=1<<21;}esp_reg_update(base+0x24,1<<21,enable);}
    let result=esp_uart_bus_update(bus);esp32_irq_restore(ps);return result;
}

// Wait for both FIFO drain and the final TX shift-register stop bit.
fn esp_uart_bus_flush(bus,cycles) {
    let base=esp_uart_bus_base(bus);if base<0 {return base;}if cycles<0 || cycles>2147483647 {return -22;}
    let fsm=base+0x6c;if rv_hal_chip==13 {fsm=base+0x70;}let start=esp32_cycles();
    while ((esp32_load32(base+0x1c)>>16)&rv_hal_uart_mask) || ((esp32_load32(fsm)>>4)&15) {if ((esp32_cycles()-start)&4294967295)>=cycles {return -110;}}return 0;
}
