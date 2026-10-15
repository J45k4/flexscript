import "esp32.flex";
// Original ESP32, 40 MHz crystal -> 320 MHz PLL -> 80 MHz CPU/APB.
// ESP-IDF v5.5.1 rtc_clk.c and esp-hal 0f0ebd92 soc/esp32/clocks.rs.
fn esp_radio_pll_byte(reg,value) {return esp32_call32(esp32_external("rom_i2c_writeReg"),0x66,4,reg,value,0,0,0,0);}
fn esp_radio_clock_init() {
    esp_uart_flush();let ps=esp32_irq_save();
    // Select undivided XTAL before changing PLL configuration.
    esp32_store32(0x3ff66000,esp32_load32(0x3ff66000)&~1023);
    esp32_store32(0x3ff48070,esp32_load32(0x3ff48070)&~(3<<27));
    esp32_call32(esp32_external("ets_update_cpu_frequency_rom"),40,0,0,0,0,0,0,0);
    esp32_store32(0x3ff48000,esp32_load32(0x3ff48000)&~((1<<18)|(1<<10)|(1<<8)|(1<<6)));
    esp_radio_pll_byte(0,0x18);esp_radio_pll_byte(1,0x20);esp_radio_pll_byte(4,0x9a);esp_radio_pll_byte(10,0);esp_radio_pll_byte(12,0);
    esp32_store32(0x3ff4807c,(esp32_load32(0x3ff4807c)&~(7<<11))|(4<<11));
    esp_radio_pll_byte(11,0x43);esp_radio_pll_byte(9,0x84);esp_radio_pll_byte(2,0);esp_radio_pll_byte(3,32);esp_radio_pll_byte(5,0xc6);
    esp32_call32(esp32_external("ets_delay_us"),160,0,0,0,0,0,0,0);
    esp32_store32(0x3ff0003c,esp32_load32(0x3ff0003c)&~3);
    esp32_store32(0x3ff48070,(esp32_load32(0x3ff48070)&~(3<<27))|(1<<27));
    esp32_call32(esp32_external("ets_update_cpu_frequency_rom"),80,0,0,0,0,0,0,0);
    esp32_store32(0x3ff480b0,0x00280028);let freq=(80000000>>12)&65535;esp32_store32(0x3ff480b4,freq|(freq<<16));
    // UART0 uses APB; retain 115200 baud after the APB clock transition.
    esp32_store32(0x3ff40014,694|(7<<20));esp32_irq_restore(ps);return 0;
}
// Raise CPU only; 320 MHz PLL / 2 gives 160 MHz, APB remains 80 MHz.
fn esp_radio_cpu160() {
    let ps=esp32_irq_save();esp32_store32(0x3ff0003c,(esp32_load32(0x3ff0003c)&~3)|1);
    esp32_call32(esp32_external("ets_update_cpu_frequency_rom"),160,0,0,0,0,0,0,0);esp32_irq_restore(ps);return 0;
}
