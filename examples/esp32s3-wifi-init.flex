// Full vendor station initialization,MAC read and orderly stop/deinit.
// No credentials or connection request; physical RF still needs an S3 board.
import "../lib/platform/esp32s3-xip.flex";
import "../lib/platform/esp32s3-sdk-preempt.flex";
import "../lib/platform/esp32s3-wifi.flex";
global s3_wifi_stage=0;
fn main() {
    let arena=esp_sdk_heap_min();if esp_sdk_heap_init(arena,esp_sdk_heap_max()-arena) || esp_sdk_task_init() {return 1;}esp_irq_enable();
    if esp_sdk_preempt_start(5000) {return 2;}let before=esp_sdk_heap_free();s3_wifi_stage=1;esp_uart_write("S3 WIFI: entering actual vendor initialization\r\n");
    let result=esp_wifi_station_init();s3_wifi_stage=2;esp_uart_write("S3 WIFI: init result=");esp_uart_hex(result);esp_uart_write(" cleanup=");esp_uart_hex(esp_wifi_cleanup_error);esp_uart_write("\r\n");if result {return 3;}
    let p=esp_sdk_calloc(1,16);if !p {return 4;}result=esp32_call32(esp32_external("esp_wifi_get_mac"),0,p,0,0,0,0,0,0);if result || esp_radio_cb_read_mac(p+8,0,0,0,0,0,0,0) {return 5;}
    let i=0;while i<6 {if load8(p+i)!=load8(p+8+i) {return 6;}i=i+1;}esp_sdk_free(p);s3_wifi_stage=3;
    result=esp_wifi_station_deinit();esp_uart_write("S3 WIFI: deinit result=");esp_uart_hex(result);esp_uart_write("\r\n");if result || esp_wifi_power_owned || esp_radio_owner || esp_sdk_heap_free()!=before {return 7;}
    if esp_sdk_preempt_stop() {return 8;}s3_wifi_stage=4;esp_uart_write("PASS: S3 actual Wi-Fi initialization,MAC and shutdown with recovered heap\r\n");return 0;
}
