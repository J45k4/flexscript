import "../../lib/platform/esp32-nvs.flex";
import "../../lib/platform/esp32-tls.flex";
fn main() {
    if esp_sdk_heap_init(0x3ffc8000,98304) || esp_sdk_task_init() {return 1;}esp32_irq_restore(0);
    let r=esp_nvs_init(0x3e0000,4096,0);if r {return 2;}
    if esp_wifi_station_init() {return 5;}
    esp_tls_set_time(1792022400);if esp_tls_add_ca("deliberately invalid fixture",27)!=0 {return 3;}
    if esp_tls_connect(0x08080808,443,51000,"example.com",11,1000) {return 4;}
    esp_tls_poll();esp_tls_send("x",1);esp_tls_receive(alloc(16),16);esp_tls_close();esp_tls_reset_session();esp_tls_deinit();return 0;
}
