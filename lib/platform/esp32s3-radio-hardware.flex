import "esp32-analog-state.flex";
import "esp32-radio-random.flex";
// ESP32-S3 MMIO operands: pinned ESP-IDF/esp-hal definitions.
fn esp_radio_random_word() {return esp32_load32(0x6003507c);}
fn esp_radio_cb_slowclk_cal(a,b,c,d,e,f,g,h) {return esp32_load32(0x60008054)>>7;}
fn esp_radio_cb_wifi_clock_on(a,b,c,d,e,f,g,h) {return 0;}
fn esp_radio_cb_wifi_clock_off(a,b,c,d,e,f,g,h) {return 0;}
fn esp_radio_cb_wifi_reset(a,b,c,d,e,f,g,h) {let ps=esp32_irq_save();let before=esp32_load32(0x60026018);esp32_store32(0x60026018,before|4);esp32_store32(0x60026018,before&~4);esp32_irq_restore(ps);return 0;}
fn esp_radio_cb_read_mac(a,b,c,d,e,f,g,h) {if !a || b<0 || b>2 {return -1;}let lo=esp32_load32(0x60007044);let hi=esp32_load32(0x60007048);let mac=(((hi&65535)<<32)|lo)+b;let i=0;while i<6 {store8(a+i,mac>>(40-i*8));i=i+1;}return 0;}
fn esp_radio_clocks_init() {let ps=esp32_irq_save();let value=esp32_load32(0x60026014);esp32_store32(0x60026014,(value&~0x3020)|0x00fb9fcf);esp32_irq_restore(ps);return 0;}
fn esp_radio_phy_clock(enable) {
    if enable!=0 && enable!=1 {return -22;}let ps=esp32_irq_save();
    if enable && esp_adc_busy {esp32_irq_restore(ps);return -16;}
    if enable && esp_radio_phy_clock_refs==9223372036854775807 {esp32_irq_restore(ps);return -75;}
    if enable {if !esp_radio_phy_clock_refs {esp32_store32(0x60026014,esp32_load32(0x60026014)|0x78078f);}esp_radio_phy_clock_refs=esp_radio_phy_clock_refs+1;}
    else if esp_radio_phy_clock_refs {esp_radio_phy_clock_refs=esp_radio_phy_clock_refs-1;if !esp_radio_phy_clock_refs {esp32_store32(0x60026014,esp32_load32(0x60026014)&~0x78078f);}}
    esp32_irq_restore(ps);return 0;
}
