import "esp32s3-radio-hardware.flex";
// Internal S3 modem power transaction. The caller owns the radio domain and
// has checked ADC/PHY users and complete IRQ capacity before entering here.
// Pass the resolved ROM delay address so host operand spies need no ESP ABI.
fn esp_radio_modem_power_on(delay) {
    if delay<=0 || delay>>32 {return -22;}let ps=esp32_irq_save();
    esp_radio_clocks_init();esp32_store32(0x60008090,esp32_load32(0x60008090)&~(1<<17));
    esp32_call32(delay,10,0,0,0,0,0,0,0);
    let before=esp32_load32(0x60026018);esp32_store32(0x60026018,before|0x2a1f);
    // Read again as in the primary implementation; preserve unrelated changes.
    before=esp32_load32(0x60026018);esp32_store32(0x60026018,before&~0x2a1f);
    esp32_store32(0x60008094,esp32_load32(0x60008094)&~(1<<28));
    esp32_irq_restore(ps);return 0;
}
fn esp_radio_modem_power_off() {
    let ps=esp32_irq_save();
    esp32_store32(0x60008094,esp32_load32(0x60008094)|(1<<28));
    esp32_store32(0x60008090,esp32_load32(0x60008090)|(1<<17));
    esp32_irq_restore(ps);return 0;
}
