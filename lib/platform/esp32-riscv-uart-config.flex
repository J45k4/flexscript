// Explicit UART0/1 initialization uses the profile's 40MHz XTAL. No LP UART.
// Reconfiguration requires a quiescent port: no IRQ enables, FIFO data or FSM
// activity. Config APIs are task-only. External peers must be quiescent too.
fn esp_uart_bus_enabled(bus) {
    let base=esp_uart_bus_base(bus);if base<0 {return base;}
    if rv_hal_chip==13 {return esp32_load32(0x60096000+bus*12)&1;}
    return (esp32_load32(0x600c0010)>>(2+bus*3))&1;
}
fn esp_uart_bus_busy(bus) {
    let base=esp_uart_bus_base(bus);if base<0 {return base;}
    if esp32_load32(esp32_state()+16) {return 1;}
    let fsm=base+0x6c;if rv_hal_chip==13 {if esp32_load32(base+0x98)&1 {return 1;}if esp32_load32(0x60096000+bus*12)&2 {return 1;}fsm=base+0x70;}else {let sync=esp32_load32(base+0x80);if (sync&(1<<31)) && !(sync&(1<<30)) {return 1;}if (esp32_load32(0x600c0018)&(1<<(2+bus*3))) || (esp32_load32(base+0x78)&((1<<23)|(3<<26))) {return 1;}}
    return esp32_load32(base+12) || (esp32_load32(base+0x1c)&(rv_hal_uart_mask|(rv_hal_uart_mask<<16))) || (esp32_load32(fsm)&255);
}
fn esp_uart_bus_init(bus,baud,data_bits,parity,stop_code) {
    let base=esp_uart_bus_base(bus);if base<0 {return base;}
    if baud<1 || baud>5000000 || data_bits<5 || data_bits>8 || parity<0 || parity>2 || stop_code<1 || stop_code>3 {return -22;}
    let pre=(40000000+4095*baud-1)/(4095*baud);if pre<1 || pre>256 {return -22;}
    let divider=640000000/(baud*pre);if divider<16 || divider>65535 {return -22;}
    let ps=esp32_irq_save();let enabled=esp_uart_bus_enabled(bus);
    if esp32_load32(esp32_state()+16) || (enabled && esp_uart_bus_busy(bus)) {esp32_irq_restore(ps);return -16;}
    let clock=base+0x78;
    if rv_hal_chip==13 {
        let control=0x60096000+bus*12;clock=control+4;
        if !enabled {esp_reg_update(control,3,3);esp_reg_update(control,2,0);}
        esp_reg_update(clock,0x7fffff,(3<<20)|(1<<22)|((pre-1)<<12));
    }else {
        let bit=1<<(2+bus*3);
        if !enabled {
            // Pinned C3 reset workaround holds the core before opening its gate.
            esp_reg_update(0x600c0018,bit,0);esp_reg_update(clock,1<<23,1<<23);esp_reg_update(0x600c0010,bit,bit);
            esp_reg_update(0x600c0018,bit,bit);esp_reg_update(0x600c0018,bit,0);esp_reg_update(clock,1<<23,0);
        }
        esp_reg_update(base+0x80,1<<30,0);
        esp_reg_update(clock,0x37fffff,(3<<20)|(1<<22)|(3<<24)|((pre-1)<<12));
    }
    esp_reg_update(base+0x14,0xf00fff,(divider>>4)|((divider&15)<<20));
    let format=((data_bits-5)<<2)|(stop_code<<4);if parity {format=format|2;if parity==2 {format=format|1;}}
    let tx_flow=1<<15;if rv_hal_chip==13 {tx_flow=1<<13;}
    esp_reg_update(base+0x20,63|tx_flow,format);
    if rv_hal_chip==13 {esp_reg_update(base+0x2c,1<<8,0);}else {esp_reg_update(base+0x24,1<<20,0);}
    esp32_store32(base+0x10,0x7ffff);let result=esp_uart_bus_update(bus);esp32_irq_restore(ps);return result;
}
// Actual divider-derived integer baud for the selected 40MHz XTAL profile.
fn esp_uart_bus_baud(bus) {
    let base=esp_uart_bus_base(bus);if base<0 {return base;}if !esp_uart_bus_enabled(bus) {return -19;}let ps=esp32_irq_save();
    let clock=base+0x78;if rv_hal_chip==13 {clock=0x60096004+bus*12;}let config=esp32_load32(clock);let div=esp32_load32(base+0x14);
    let value= -95;if ((config>>20)&3)==3 && !(config&4095) {let factor=((div&4095)<<4)|((div>>20)&15);if factor>=16 {value=640000000/(factor*(((config>>12)&255)+1));}}
    esp32_irq_restore(ps);return value;
}
// mode bit0=RTS receive throttling, bit1=CTS transmit gating. Pins are separate.
fn esp_uart_bus_flow(bus,mode,rx_threshold) {
    let base=esp_uart_bus_base(bus);if base<0 {return base;}
    if mode<0 || mode>3 || rx_threshold<0 || rx_threshold>127 || ((mode&1) && !rx_threshold) {return -22;}
    let ps=esp32_irq_save();if !esp_uart_bus_enabled(bus) {esp32_irq_restore(ps);return -19;}if esp_uart_bus_busy(bus) {esp32_irq_restore(ps);return -16;}
    let tx=0;if mode&2 {tx=1;}
    if rv_hal_chip==13 {let receive=0;if mode&1 {receive=rx_threshold|256;}esp_reg_update(base+0x2c,511,receive);esp_reg_update(base+0x20,1<<13,tx<<13);}
    else {if mode&1 {esp_reg_update(base+0x60,511<<7,rx_threshold<<7);}let receive=0;if mode&1 {receive=1<<20;}esp_reg_update(base+0x24,1<<20,receive);esp_reg_update(base+0x20,1<<15,tx<<15);}
    let result=esp_uart_bus_update(bus);esp32_irq_restore(ps);return result;
}
// -1 leaves a signal untouched. Reject every argument and duplicate pad before
// any route/mux write. UART0/1 signals6/9 and7/10 are shared by both chips.
fn esp_uart_bus_pins(bus,tx,rx,rts,cts) {
    let base=esp_uart_bus_base(bus);if base<0 {return base;}
    if (tx!= -1 && !esp_gpio_valid(tx)) || (rx!= -1 && !esp_gpio_valid(rx)) || (rts!= -1 && !esp_gpio_valid(rts)) || (cts!= -1 && !esp_gpio_valid(cts)) {return -22;}
    if (tx>=0 && (tx==rx || tx==rts || tx==cts)) || (rx>=0 && (rx==rts || rx==cts)) || (rts>=0 && rts==cts) {return -22;}
    let ps=esp32_irq_save();if esp32_load32(esp32_state()+16) || (esp_uart_bus_enabled(bus) && esp_uart_bus_busy(bus)) {esp32_irq_restore(ps);return -16;}
    let signal=6+bus*3;
    if tx>=0 {esp_gpio_write(tx,1);esp_gpio_open_drain(tx,0);esp_gpio_route_output(tx,signal);}
    if rx>=0 {esp_gpio_input(rx,1);esp_gpio_route_input(rx,signal);}
    if rts>=0 {esp_gpio_write(rts,1);esp_gpio_open_drain(rts,0);esp_gpio_route_output(rts,signal+1);}
    if cts>=0 {esp_gpio_input(cts,1);esp_gpio_route_input(cts,signal+1);}
    esp32_irq_restore(ps);return 0;
}
