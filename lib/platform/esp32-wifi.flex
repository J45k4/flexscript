import "esp32-radio-os.flex";
import "esp32-wifi-core.flex";
fn esp_wifi_platform_busy() {return esp_irq_handler(0)!=0;}
fn esp_wifi_platform_prepare() {
    let ps=esp32_irq_save();if esp_radio_owner!=1 || esp_adc_busy {esp32_irq_restore(ps);return -16;}
    let result=esp_irq_reserve(!esp_irq_handler(0));if result {esp32_irq_restore(ps);return result;}
    esp32_store32(0x3ff000cc,4294967295);esp32_store32(0x3ff48084,esp32_load32(0x3ff48084)&~(1<<17));esp32_call32(esp32_external("ets_delay_us"),10,0,0,0,0,0,0,0);esp32_store32(0x3ff48088,esp32_load32(0x3ff48088)&~(1<<28));
    esp32_irq_restore(ps);return 0;
}
fn esp_wifi_platform_release() {return 0;}
