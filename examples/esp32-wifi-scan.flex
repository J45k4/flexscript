import "../lib/platform/esp32-xip.flex";
import "../lib/platform/esp32-radio-os.flex";
import "../lib/platform/esp32-radio-clock.flex";
fn wifi_word(label,value) {esp_uart_write(label);esp_uart_hex(value);esp_uart_write("\r\n");return value;}
fn main() {
    esp_uart_write("Flexscript Wi-Fi scan probe\r\n");esp_radio_clock_init();
    if esp_sdk_heap_init(0x3ffc8000,98304) || esp_sdk_task_init() || esp_radio_os_init() {return 1;}
    esp32_store32(esp32_external("WIFI_EVENT"),"WIFI_EVENT");
    esp32_store32(0x3ff000cc,4294967295);
    esp32_store32(0x3ff48084,esp32_load32(0x3ff48084)&~(1<<17));
    esp32_call32(esp32_external("ets_delay_us"),10,0,0,0,0,0,0,0);
    esp32_store32(0x3ff48088,esp32_load32(0x3ff48088)&~(1<<28));
    let mac=esp_sdk_calloc(1,8);esp_radio_cb_read_mac(mac,0,0,0,0,0,0,0);wifi_word("MAC ",load64(mac));esp_sdk_free(mac);
    let config=esp_sdk_calloc(1,160);if !config {return 2;}esp32_store32(config,esp_radio_osi);
    let crypto=esp32_external("g_wifi_default_wpa_crypto_funcs");let i=0;while i<52 {store8(config+4+i,load8(crypto+i));i=i+1;}
    esp32_store32(config+56,4);esp32_store32(config+60,8);esp32_store32(config+64,1);esp32_store32(config+68,0);esp32_store32(config+72,8);
    esp32_store32(config+76,0);esp32_store32(config+80,5);esp32_store32(config+112,6);esp32_store32(config+120,752);esp32_store32(config+124,6);
    esp32_store32(config+140,0);esp32_store32(config+144,3);esp32_store32(config+152,523190095);
    esp_irq_enable();
    let result=esp32_call32(esp32_external("esp_wifi_init_internal"),config,0,0,0,0,0,0,0);wifi_word("Wi-Fi init ",result);if result {return 3;}
    result=esp32_call32(esp32_external("esp_wifi_set_mode"),1,0,0,0,0,0,0,0);wifi_word("Wi-Fi mode ",result);if result {return 4;}
    result=esp32_call32(esp32_external("esp_supplicant_init"),0,0,0,0,0,0,0,0);wifi_word("Wi-Fi supplicant ",result);if result {return 10;}
    result=esp32_call32(esp32_external("esp_wifi_start"),0,0,0,0,0,0,0,0);wifi_word("Wi-Fi start ",result);if result {return 5;}
    result=esp32_call32(esp32_external("esp_wifi_set_ps"),0,0,0,0,0,0,0,0);wifi_word("Wi-Fi awake ",result);if result {return 6;}
    // Zeroed scan config is all channels; passive scanning emits no probe request.
    let scan=esp_sdk_calloc(1,64);esp32_store32(scan+12,1);esp32_store32(scan+24,120);
    result=esp32_call32(esp32_external("esp_wifi_scan_start"),scan,0,0,0,0,0,0,0);wifi_word("Wi-Fi scan start ",result);if result {return 7;}
    let deadline=esp_sdk_now()+20000000;while !esp_radio_scan_done && esp_sdk_now()<deadline {esp_sdk_delay(1);}if !esp_radio_scan_done {wifi_word("Scan timeout IRQ count ",esp_radio_irq_count);wifi_word("IRQ raw ",esp32_load32(0x3ff000ec));wifi_word("IRQ enabled ",esp32_irq_enabled());wifi_word("IRQ pending ",esp32_irq_pending());wifi_word("Wi-Fi clocks ",esp32_load32(0x3ff000cc));wifi_word("Timer yields ",esp_sdk_yields);return 8;}wifi_word("Wi-Fi scan status ",esp_radio_scan_status);if esp_radio_scan_status {return 11;}
    let count=esp_sdk_calloc(1,4);result=esp32_call32(esp32_external("esp_wifi_scan_get_ap_num"),count,0,0,0,0,0,0,0);wifi_word("Wi-Fi scan count ",load8(count)|(load8(count+1)<<8));if result {return 9;}
    if !(load8(count)|(load8(count+1)<<8)) {return 12;}
    esp_uart_write("PASS: physical Wi-Fi passive scan\r\n");esp_uart_flush();return 0;
}
