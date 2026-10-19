// Shared C3/C6 adapter. Chip module supplies bases and conservative flash-pad policy.
// ESP-IDF v5.5.1 reg_base/gpio/io_mux/uart headers are the register reference.
fn esp_riscv_ready() {return esp32_state()==rv_hal_state;}
fn esp_uart_putc(byte) {if !esp_riscv_ready() {return -95;}while ((esp32_load32(0x6000001c)>>16)&rv_hal_uart_mask)>=126 {}esp32_store32(0x60000000,byte&255);return 0;}
fn esp_uart_write(text) {let i=0;while load8(text+i) {let status=esp_uart_putc(load8(text+i));if status {return status;}i=i+1;}return i;}
fn esp_uart_hex(value) {let alphabet="0123456789abcdef";let shift=60;while shift>=0 {let status=esp_uart_putc(load8(alphabet+((value>>shift)&15)));if status {return status;}shift=shift-4;}return 0;}
fn esp_uart_flush() {if !esp_riscv_ready() {return -95;}while ((esp32_load32(0x6000001c)>>16)&rv_hal_uart_mask) {}return 0;}
fn esp_uart_read() {if !esp_riscv_ready() {return -95;}if !(esp32_load32(0x6000001c)&rv_hal_uart_mask) {return -1;}return esp32_load32(0x60000000)&255;}
fn esp_gpio_valid(pin) {return esp_riscv_ready() && pin>=0 && pin<=rv_hal_pin_max && (pin<rv_hal_reserved_start || pin>rv_hal_reserved_end);}
fn esp_gpio_mux(pin) {if !esp_gpio_valid(pin) {return -22;}let address=rv_hal_mux+4+pin*4;let ps=esp32_irq_save();esp32_store32(address,(esp32_load32(address)&~0x7000)|0x1200);esp32_irq_restore(ps);return 0;}
fn esp_gpio_write(pin,high) {if !esp_gpio_valid(pin) {return -22;}let offset=12;if high {offset=8;}esp32_store32(rv_hal_gpio+offset,1<<pin);return 0;}
fn esp_gpio_output(pin) {if !esp_gpio_valid(pin) {return -22;}esp_gpio_mux(pin);esp32_store32(rv_hal_gpio+0x554+pin*4,128|512);esp32_store32(rv_hal_gpio+0x24,1<<pin);return 0;}
fn esp_gpio_pull(pin,pull) {if !esp_gpio_valid(pin) || pull<0 || pull>2 {return -22;}let address=rv_hal_mux+4+pin*4;let bits=0;if pull==1 {bits=256;}else if pull==2 {bits=128;}let ps=esp32_irq_save();esp32_store32(address,(esp32_load32(address)&~384)|bits);esp32_irq_restore(ps);return 0;}
fn esp_gpio_input(pin,pull) {if !esp_gpio_valid(pin) || pull<0 || pull>2 {return -22;}esp_gpio_mux(pin);esp32_store32(rv_hal_gpio+0x28,1<<pin);return esp_gpio_pull(pin,pull);}
fn esp_gpio_read(pin) {if !esp_gpio_valid(pin) {return -22;}return (esp32_load32(rv_hal_gpio+0x3c)>>pin)&1;}
fn esp_gpio_open_drain(pin,enable) {if !esp_gpio_valid(pin) {return -22;}let address=rv_hal_gpio+0x74+pin*4;let bits=0;if enable {bits=4;}let ps=esp32_irq_save();esp32_store32(address,(esp32_load32(address)&~4)|bits);esp32_irq_restore(ps);return 0;}
fn esp_delay_cycles(cycles) {if cycles<0 || cycles>2147483647 {return -22;}let start=esp32_cycles();while ((esp32_cycles()-start)&0xffffffff)<cycles {}return 0;}

fn esp_reg_update(address,mask,value) {let ps=esp32_irq_save();esp32_store32(address,(esp32_load32(address)&~mask)|(value&mask));esp32_irq_restore(ps);return 0;}
fn esp_wait_mask(address,mask,value,cycles) {if cycles<0 || cycles>2147483647 {return -22;}let start=esp32_cycles();while (esp32_load32(address)&mask)!=value {if ((esp32_cycles()-start)&4294967295)>=cycles {return -110;}}return 0;}
fn esp_buffer_valid(buffer,size) {if !esp_riscv_ready() || buffer<rv_hal_state+56 || size<0 {return 0;}return buffer<=rv_hal_ram_top && size<=rv_hal_ram_top-buffer;}
