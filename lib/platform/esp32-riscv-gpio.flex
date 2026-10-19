// Optional GPIO matrix and pin IRQ adapter. The chip entry imports its pad policy.
// Source handlers are attached explicitly through the matching -irq module.
fn esp_gpio_route_output(pin,signal) {
    if !esp_gpio_valid(pin) || signal<0 || signal>128 {return -22;}let ps=esp32_irq_save();
    esp_gpio_output(pin);esp32_store32(rv_hal_gpio+0x554+pin*4,signal|512);esp32_irq_restore(ps);return 0;
}
fn esp_gpio_route_input(pin,signal) {
    if !esp_gpio_valid(pin) || signal<0 || signal>=128 {return -22;}let ps=esp32_irq_save();
    esp_gpio_mux(pin);let select=64;if rv_hal_chip==13 {select=128;}esp32_store32(rv_hal_gpio+0x154+signal*4,pin|select);esp32_irq_restore(ps);return 0;
}
// mode0 disables;1 rising,2 falling,3 any edge,4 low level,5 high level.
// This API owns the pin's entire INT_ENA field and clears its stale latch.
fn esp_gpio_irq(pin,mode) {
    if !esp_gpio_valid(pin) || mode<0 || mode>5 {return -22;}let ps=esp32_irq_save();let address=rv_hal_gpio+0x74+pin*4;
    esp_reg_update(address,31<<13,0);esp_reg_update(address,7<<7,mode<<7);esp32_store32(rv_hal_gpio+0x4c,1<<pin);
    if mode {esp_reg_update(address,31<<13,1<<13);}esp32_irq_restore(ps);return 0;
}
fn esp_gpio_irq_source() {if !esp_riscv_ready() {return -95;}if rv_hal_chip==13 {return 30;}return 16;}
// Raw per-pin status remains observable independently of CPU line masking.
fn esp_gpio_irq_pending(pin) {if !esp_gpio_valid(pin) {return -22;}return (esp32_load32(rv_hal_gpio+0x44)>>pin)&1;}
fn esp_gpio_irq_ack(pin) {if !esp_gpio_valid(pin) {return -22;}esp32_store32(rv_hal_gpio+0x4c,1<<pin);return 0;}
