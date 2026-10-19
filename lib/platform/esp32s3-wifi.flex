import "esp32s3-radio-os.flex";
import "esp32-wifi-core.flex";
import "esp32s3-radio-power.flex";
// The S3 modem is shared with Bluetooth; the radio domain lease excludes it.
global esp_wifi_power_owned=0;
fn esp_wifi_platform_busy() {return esp_wifi_power_owned || esp_irq_handler(0) || esp_irq_handler(2);}
fn esp_wifi_platform_prepare() {
    let ps=esp32_irq_save();if esp_radio_owner!=1 || esp_adc_busy || esp_radio_phy_refs || esp_radio_phy_clock_refs || esp_wifi_power_owned {esp32_irq_restore(ps);return -16;}
    let result=esp_radio_irq_can_claim(0,esp32_callback(esp_radio_irq));if !result {result=esp_radio_irq_can_claim(2,esp32_callback(esp_radio_irq));}
    if !result {result=esp_irq_reserve(!esp_irq_handler(0)+!esp_irq_handler(2));}if result {esp32_irq_restore(ps);return result;}
    result=esp_radio_modem_power_on(esp32_external("ets_delay_us"));if result {esp32_irq_restore(ps);return result;}
    esp_wifi_power_owned=1;esp32_irq_restore(ps);return 0;
}
fn esp_wifi_platform_release() {
    let ps=esp32_irq_save();if !esp_wifi_power_owned {esp32_irq_restore(ps);return 0;}
    if esp_radio_owner!=1 || esp_radio_phy_refs || esp_radio_phy_clock_refs || esp_adc_busy {esp32_irq_restore(ps);return -16;}
    // PHY shutdown and vendor task quiescence precede power-domain isolation.
    esp_radio_modem_power_off();
    esp_wifi_power_owned=0;esp32_irq_restore(ps);return 0;
}

fn esp_wifi_platform_reset_locks(){esp32_store32(esp32_external("s_wifi_api_lock"),0);esp32_store32(esp32_external("g_wifi_global_lock"),0);esp32_store32(esp32_external("eloop_data_lock"),0);return 0;}
