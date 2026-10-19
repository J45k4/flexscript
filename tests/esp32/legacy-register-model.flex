import "../../lib/platform/esp32-timer.flex";
global lr_regs=0;
global lr_count=0;
global lr_fifo_reads=0;
global lr_ps=0;
global lr_irq_fault=0;
global lr_status_reads=0;
global lr_status_drain=0;
fn lr_index(address) {let i=0;while i<lr_count {if load64(lr_regs+i*16)==address {return i;}i=i+1;}store64(lr_regs+i*16,address);lr_count=lr_count+1;return i;}
fn esp32_load32(address) {
    if address==0x3ff40000 {lr_fifo_reads=lr_fifo_reads+1;if !lr_ps {lr_irq_fault=1;}}
    if address==0x3ff4001c {lr_status_reads=lr_status_reads+1;if lr_status_drain && lr_status_reads>=lr_status_drain {return 0;}}
    return load64(lr_regs+lr_index(address)*16+8);}
fn esp32_store32(address,value) {store64(lr_regs+lr_index(address)*16+8,value&4294967295);return 0;}
fn esp32_irq_save() {let old=lr_ps;lr_ps=15;return old;}
fn esp32_irq_restore(ps) {lr_ps=ps;return 0;}
fn esp32_cycles() {return 0;}
fn main() {
    lr_regs=alloc(16384);
    if esp_gpio_mux_address(0)!=0x3ff49044 || esp_gpio_mux_address(1)!=0x3ff49088 || esp_gpio_mux_address(39)!=0x3ff49010 {return 1;}
    esp32_store32(0x3ff48494,1<<19);if esp_gpio_input(4,1) || (esp32_load32(0x3ff48494)&(1<<19)) || esp32_load32(0x3ff49048)!=0x2200 || !(esp32_load32(0x3ff48494)&(1<<27)) {return 2;}
    if esp_gpio_input(34,0) || esp_gpio_input(34,1)!= -22 || esp_gpio_output(34)!= -22 || esp_gpio_route_output(35,0)!= -22 {return 3;}
    if esp_gpio_output(20)!= -22 || esp_gpio_output(24)!= -22 || esp_gpio_output(28)!= -22 || esp_gpio_output(40)!= -22 {return 4;}
    if esp_gpio_interrupt(4,3) || esp32_load32(0x3ff44098)!=(0x8000|384) {return 5;}
    if esp_timer_init(0,80,0) || esp32_load32(0x3ff5f000)!=0x400a0800 || esp_timer_init(0,80,1)!= -22 {return 6;}
    if esp_timer_alarm(0,100,0) || !(esp32_load32(0x3ff5f098)&1) || !(esp32_load32(0x3ff5f000)&1024) {return 7;}
    if esp_timer_source(0)!=14 || esp_timer_source(3)!=19 {return 8;}
    // UART_STATUS: RX count[7:0], RX state[11:8], TX count[23:16],
    // TX state[27:24]. A byte still shifting in is not a FIFO byte.
    let state=0;while state<16 {esp32_store32(0x3ff4001c,state<<8);if esp_uart_read()!= -1 || lr_fifo_reads || lr_ps {return 9;}state=state+1;}
    esp32_store32(0x3ff40000,0xab);esp32_store32(0x3ff4001c,(7<<8)|1);lr_ps=3;if esp_uart_read()!=0xab || lr_fifo_reads!=1 || lr_irq_fault || lr_ps!=3 {return 10;}lr_ps=0;
    lr_status_drain=64;state=0;while state<15 {lr_status_reads=0;esp32_store32(0x3ff4001c,state<<24);esp_uart_putc(90);if lr_status_reads!=1 || esp32_load32(0x3ff40000)!=90 {return 11;}state=state+1;}
    lr_status_reads=0;lr_status_drain=3;esp32_store32(0x3ff4001c,4<<24);esp_uart_flush();if lr_status_reads!=3 {return 12;}return 0;
}
