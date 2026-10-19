import "esp32-wifi-core.flex";
// CPU0 standalone Wi-Fi; the native radio wrapper supplies chip ownership.
fn esp_wifi_platform_busy(){return esp_radio_hw_ready || esp_radio_regi2c_active || esp_radio_pmu_active || esp_irq_handler(0) || esp_irq_handler(2);}
fn esp_wifi_platform_prepare(){
 let ps=esp32_irq_save();if esp_radio_owner!=1 || esp_adc_busy || esp_radio_phy_refs || esp_radio_phy_clock_refs || esp_radio_regi2c_active || esp_radio_pmu_active{esp32_irq_restore(ps);return -16;}
 let handler=esp32_iram_callback(esp_radio_irq);let result=esp_radio_riscv_claimable(0,handler);if !result{result=esp_radio_riscv_claimable(2,handler);}if !result{result=esp_irq_reserve(!esp_irq_handler(0)+!esp_irq_handler(2));}if !result{result=esp_radio_hardware_init();}esp32_irq_restore(ps);return result;
}
fn esp_wifi_platform_release(){return esp_radio_hardware_deinit();}
fn esp_wifi_platform_reset_locks(){esp32_store32(esp32_external("s_wifi_api_lock"),0);esp32_store32(esp32_external("eloop_data_lock"),0);return 0;}
