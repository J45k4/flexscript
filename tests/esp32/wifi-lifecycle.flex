import "../../lib/platform/esp32-xip.flex";
import "../../lib/platform/esp32-wifi.flex";
import "radio-lifecycle-probe.flex";
fn lp_scan() {
    esp_radio_scan_done=0;esp_radio_scan_status= -1;let scan=esp_sdk_calloc(1,64);let count=esp_sdk_calloc(1,4);if !scan || !count {return 1;}
    esp32_store32(scan+12,1);esp32_store32(scan+24,120);let r=esp32_call32(esp32_external("esp_wifi_scan_start"),scan,0,0,0,0,0,0,0);if r {return r;}
    let deadline=esp_sdk_now()+20000000;while !esp_radio_scan_done && esp_sdk_now()<deadline {esp_sdk_delay(1);}if !esp_radio_scan_done || esp_radio_scan_status {return 2;}
    r=esp32_call32(esp32_external("esp_wifi_scan_get_ap_num"),count,0,0,0,0,0,0,0);lp_word("APS ",load8(count)|(load8(count+1)<<8));esp_sdk_free(scan);esp_sdk_free(count);return r;
}
fn main() {
    esp_uart_write("LIFECYCLE PROBE WIFI\r\n");let r=lp_init();if r {return r;}let round=0;
    while round<4 {if round==2 {if lp_shared() {return 4;}}lp_word("CYCLE ",round);r=esp_wifi_station_init();lp_word("INIT ",r);if r {return 5;}
        if esp_wifi_station_init()!= -16 {return 6;}r=lp_scan();if r {lp_word("SCAN ERROR ",r);return 7;}
        r=esp_wifi_station_stop();lp_word("STOP ",r);if r || esp_wifi_started || esp_wifi_linked || esp_wifi_want_link || esp_wifi_retry_at {return 8;}
        if esp_wifi_station_start() {return 9;}r=esp_wifi_station_deinit();lp_word("DEINIT ",r);if r {return 10;}
        if esp_wifi_station_deinit() || esp_wifi_station_start()!= -19 || esp_wifi_station_stop()!= -19 || esp_wifi_initialized || esp_wifi_rx_ring || esp_radio_isr || esp_radio_osi {return 11;}
        r=lp_check();lp_word("OWNERSHIP CHECK ",r);if r {return 12;}round=round+1;
    }
    esp_uart_write("SUPPLICANT DEINIT 0000000000000000\r\nDEINITIALIZED\r\nLIFECYCLE VENDOR RESULT 0000000000000000\r\n");esp_uart_flush();return 0;
}
