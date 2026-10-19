// Radio shares the initialized task-local newlib ABI; never redefine malloc/free.
fn esp_radio_libc_exports(){if !esp_libc_stdio_ready || !esp_libc_rom_table{return -19;}esp32_callback32(rtc_clk_xtal_freq_get);return esp_atomics_bind();}
// All current C3/C6 clock/timer profiles explicitly require a40MHz crystal.
fn rtc_clk_xtal_freq_get(a,b,c,d,e,f,g,h){return 40;}
