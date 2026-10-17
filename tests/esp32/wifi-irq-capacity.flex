import "../../lib/platform/esp32-xip.flex";
import "../../lib/platform/esp32-wifi.flex";
fn capacity_app_irq(source) {return 0;}
fn main() {
    if esp_sdk_heap_init(0x3ffc8000,98304) || esp_sdk_task_init() {return 1;}esp_irq_enable();
    let source=10;while source<42 {if esp_irq_attach(source,esp32_callback(capacity_app_irq)) {return 2;}source=source+1;}
    let baseline=esp_sdk_heap_free();let enable=esp32_irq_enabled();let clocks=esp32_load32(0x3ff000cc);let power=esp32_load32(0x3ff48084);let iso=esp32_load32(0x3ff48088);
    if esp_wifi_station_init()!= -12 || esp_wifi_cleanup_error || esp_radio_owner || esp_radio_osi || esp_wifi_rx_ring || esp_wifi_init_config || esp_sdk_heap_free()!=baseline || esp_irq_count!=32 || esp32_irq_enabled()!=enable || esp32_load32(0x3ff000cc)!=clocks || esp32_load32(0x3ff48084)!=power || esp32_load32(0x3ff48088)!=iso || esp32_load32(esp32_external("wifi_lifecycle_oracle")+36) {esp_uart_write("WIFI CAPACITY FAIL\r\n");return 3;}
    source=10;while source<42 {if esp_irq_handler(source)!=esp32_callback(capacity_app_irq) {return 4;}esp_irq_detach(source);source=source+1;}
    if esp_irq_attach(0,esp32_callback(capacity_app_irq)) || esp_wifi_station_init()!= -16 || esp_radio_owner || esp_sdk_heap_free()!=baseline || esp_irq_handler(0)!=esp32_callback(capacity_app_irq) {return 5;}esp_irq_detach(0);
    esp_uart_write("PASS: original Wi-Fi IRQ-capacity rejection preserves heap, routes, clocks, power and INTENABLE\r\n");esp_uart_flush();return 0;
}
