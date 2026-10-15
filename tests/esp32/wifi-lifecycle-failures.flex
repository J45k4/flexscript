import "../../lib/platform/esp32-xip.flex";
import "../../lib/platform/esp32-wifi.flex";
fn failure_app_irq(source) {return 0;}
fn failure_clean(baseline) {return !esp32_load32(esp32_external("s_wifi_api_lock")) && !esp32_load32(esp32_external("g_wifi_global_lock")) && !esp32_load32(esp32_external("eloop_data_lock")) && !esp_radio_owner && !esp_wifi_initialized && !esp_wifi_vendor_initialized && !esp_wifi_vendor_running && !esp_wifi_supplicant && !esp_wifi_rx_ring && !esp_wifi_init_config && !esp_radio_osi && !esp_sdk_timer_task && !load64(esp_sdk_tasks+568) && load64(esp_sdk_tasks+536)==esp_sdk_tasks && esp_sdk_heap_free()==baseline && esp_irq_count==1 && esp_irq_handler(14)==esp32_callback(failure_app_irq);}
fn main() {
    if esp_sdk_heap_init(0x3ffc8000,98304) || esp_sdk_task_init() || esp_irq_attach(14,esp32_callback(failure_app_irq)) {return 1;}esp_irq_enable();let control=esp32_external("wifi_lifecycle_oracle");let baseline=esp_sdk_heap_free();if esp_irq_attach(0,esp32_callback(failure_app_irq)) || esp_wifi_station_init()!= -16 || esp_sdk_heap_free()!=baseline || esp_irq_handler(0)!=esp32_callback(failure_app_irq) {return 14;}esp_irq_detach(0);let stage=1;
    while stage<=7 {esp32_store32(control,stage);let r=esp_wifi_station_init();if r!=700+stage || esp_wifi_cleanup_error || !failure_clean(baseline) {esp_uart_write("FAILED INIT STAGE ");esp_uart_hex(stage);esp_uart_hex(r);return 2;}stage=stage+1;}
    stage=8;while stage<=10 {esp32_store32(control,0);if esp_wifi_station_init() {return 3;}let held=esp_sdk_heap_free();let ring=esp_wifi_rx_ring;esp32_store32(control,stage);esp_wifi_want_link=1;esp_wifi_retry_at=1;
        if esp_wifi_station_deinit()!=700+stage || !esp_wifi_initialized || esp_radio_owner!=1 || esp_wifi_rx_ring!=ring || esp_wifi_want_link || esp_wifi_retry_at || esp_sdk_heap_free()!=held {return 4;}
        if stage==8 && !esp_wifi_vendor_running {return 5;}if stage==9 && !esp_wifi_vendor_initialized {return 6;}if stage==10 && (esp_wifi_vendor_initialized || !esp_wifi_supplicant) {return 7;}
        esp32_store32(control,0);if esp_wifi_station_deinit() || esp_wifi_station_deinit() || !failure_clean(baseline) {return 8;}stage=stage+1;
    }
    esp32_store32(control,7);esp32_store32(control+4,8);if esp_wifi_station_init()!=707 || esp_wifi_cleanup_error!=708 || esp_radio_owner!=1 || !esp_wifi_rx_ring {return 9;}esp32_store32(control,0);esp32_store32(control+4,0);if esp_wifi_station_deinit() || !failure_clean(baseline) {return 10;}
    let remaining=1000;while remaining<16000 {let held=esp_sdk_malloc(baseline-remaining);if !held {return 11;}let before=esp_sdk_heap_free();if esp_wifi_station_init()!= -12 || esp_wifi_cleanup_error || esp_sdk_heap_free()!=before {return 12;}esp_sdk_free(held);if !failure_clean(baseline) {return 13;}if remaining==1000 {remaining=7000;}else if remaining==7000 {remaining=15100;}else {remaining=16000;}}
    esp_uart_write("PASS: seven Wi-Fi init failures, stop/deinit/supplicant retries, failed rollback and three allocation failures\r\n");esp_uart_flush();return 0;
}
