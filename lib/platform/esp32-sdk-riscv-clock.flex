// Leases TIMG1 timer0 as a monotonic microsecond clock. C3/C6 XTAL=40MHz.
// No alarms, peripheral IRQ ownership, scheduler IRQ tail or CPU clock tuning.
fn esp_sdk_clock_base() {if !esp_riscv_ready() {return 0;}if rv_hal_chip==5 {return 0x60020000;}return 0x60009000;}
fn esp_sdk_clock_update(address,mask,value) {esp32_store32(address,(esp32_load32(address)&~mask)|(value&mask));return 0;}
fn esp_sdk_clock_init() {
    let base=esp_sdk_clock_base();if !base {return -95;}let ps=esp32_irq_save();
    if (esp32_load32(base)&(1<<31)) || ((esp32_load32(base+0x70)|esp32_load32(base+0x74))&1) {esp32_irq_restore(ps);return -16;}
    if rv_hal_chip==5 {
        esp_sdk_clock_update(0x600c0010,1<<15,1<<15);esp_sdk_clock_update(0x600c0018,1<<15,0);
    }else {esp_sdk_clock_update(0x60096048,3,1);esp_sdk_clock_update(0x6009604c,(3<<20)|(1<<22),1<<22);}
    esp_sdk_clock_update(base+0xfc,1<<30,1<<30);
    let config=(40<<13)|(1<<30);if rv_hal_chip==5 {config=config|(1<<9);}
    esp32_store32(base,config);esp32_store32(base+24,0);esp32_store32(base+28,0);esp32_store32(base+32,1);esp32_store32(base,config|(1<<31));esp32_irq_restore(ps);return 0;
}
fn esp_sdk_clock_now() {
    let base=esp_sdk_clock_base();if !base {return -95;}esp32_store32(base+12,1<<31);let start=esp32_cycles();
    while esp32_load32(base+12)&(1<<31) {if ((esp32_cycles()-start)&0xffffffff)>=1000000 {return -110;}}
    return esp32_load32(base+4)|((esp32_load32(base+8)&4194303)<<32);
}
