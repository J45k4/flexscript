// Actual pinned S3 archives and ROM scripts; no Wi-Fi/PHY initialization.
import "../lib/platform/esp32s3-xip.flex";
import "../lib/platform/esp32s3-radio-os.flex";
fn main() {
    let arena=esp_sdk_heap_min();if esp_sdk_heap_init(arena,esp_sdk_heap_max()-arena) || esp_sdk_task_init() {return 1;}
    let before=esp_sdk_heap_free();if esp_radio_os_init() {return 2;}esp32_irq_restore(0);
    let p=esp_sdk_malloc(16);if !p {return 3;}let i=0;while i<16 {store8(p+i,0xa5);i=i+1;}
    let code=esp32_call32(esp32_external("esp_wifi_get_mac"),0,p+4,0,0,0,0,0,0);
    if code!=0x3001 {esp_uart_write("S3 preinit MAC returned ");esp_uart_hex(code);return 4;}
    i=0;while i<16 {if load8(p+i)!=0xa5 {return 5;}i=i+1;}
    code=esp32_call32(esp32_external("hexstr2bin"),"deadbeef01234567",p+4,8,0,0,0,0,0);
    if code || load64(p+4)!=0x67452301efbeadde || load8(p)!=0xa5 || load8(p+15)!=0xa5 {return 6;}esp_sdk_free(p);
    if esp_radio_resources_end(esp32_callback(esp_radio_irq)) || esp_sdk_heap_free()!=before {return 7;}
    esp_radio_osi=0;esp_uart_write("PASS: S3 actual vendor MAC preinit guard,WPA bytes and native OS table cleanup\r\n");return 0;
}
