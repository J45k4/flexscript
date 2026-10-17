fn pa_ps() {let ps=esp32_irq_save();esp32_irq_restore(ps);return ps;}
fn pa_admission() {
    let initial=pa_ps();let baseline=esp_sdk_heap_free();if esp_radio_phy_buffers_init() {return 1;}
    let held=esp_sdk_heap_free();let cal=esp_radio_phy_cal;let data=esp_radio_phy_init_data;let digital=pa_digital();
    let control=esp32_external("wifi_lifecycle_oracle");let calls=esp32_load32(control+36);let enable=esp32_irq_enabled();
    let level=0;while level<16 {esp32_irq_restore((initial&~15)|level);let expected=pa_ps();let which=0;while which<6 {
        esp_radio_phy_refs=0;esp_radio_phy_clock_refs=0;
        if which==0 || which==2 {esp_radio_phy_refs=1;}if which==1 || which==2 {esp_radio_phy_clock_refs=1;}
        if which==3 || which==5 {esp_radio_phy_refs=9223372036854775807;}if which==4 || which==5 {esp_radio_phy_clock_refs=9223372036854775807;}
        let refs=esp_radio_phy_refs;let clocks=esp_radio_phy_clock_refs;
        if esp_wifi_station_init()!= -16 || esp_wifi_cleanup_error || esp_radio_owner || esp_radio_osi || esp_wifi_rx_ring || esp_wifi_init_config || esp_wifi_lifecycle_busy || esp_wifi_initialized || esp_wifi_vendor_initialized || esp_wifi_vendor_running || esp_wifi_supplicant || esp_radio_phy_cal!=cal || esp_radio_phy_init_data!=data || pa_digital()!=digital || esp_radio_phy_refs!=refs || esp_radio_phy_clock_refs!=clocks || esp_sdk_heap_free()!=held || pa_ps()!=expected || esp32_irq_enabled()!=enable || esp32_load32(control+36)!=calls {esp_uart_write("WIFI PHY ADMISSION FAIL ");esp_uart_hex(level);esp_uart_hex(which);esp_uart_write("\r\n");return 2;}
        which=which+1;}level=level+1;}
    esp32_irq_restore(initial);esp_radio_phy_refs=0;esp_radio_phy_clock_refs=0;
    if esp_radio_phy_release_buffers() || esp_sdk_heap_free()!=baseline {return 3;}return 0;
}
