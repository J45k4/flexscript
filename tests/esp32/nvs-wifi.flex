import "../../lib/platform/esp32-radio-clock.flex";
import "../../lib/platform/esp32-nvs.flex";
import "../../lib/platform/esp32-wifi.flex";
fn nn_word(label,value) {esp_uart_write(label);esp_uart_hex(value);esp_uart_write("\r\n");return value;}
fn nn_run() {
    esp_radio_clock_init();if esp_sdk_heap_init(0x3ffc8000,98304) || esp_sdk_task_init() {return 1;}
    let r=esp_nvs_init(0x3e0000,4096,1);nn_word("NVS INIT ",r);if r {return 2;}
    let out=alloc(16);let data=alloc(608);if esp_nvs_open("probe",1,out) {return 3;}let h=kv_u32(out);let previous=0;
    r=esp_nvs_get_u8(h,"count",out+4);if r==0 {previous=load8(out+4);kv_put32(out+8,608);if esp_nvs_get_blob(h,"payload",data,out+8) || kv_u32(out+8)!=600 {return 4;}let i=0;while i<600 {if load8(data+i)!=((i*29+previous)&255) {return 5;}i=i+1;}}
    else if r!=0x1102 {return 6;}nn_word("NVS RECOVERED ",previous);if previous>2 {return 7;}
    let next=previous;if next<2 {next=next+1;let i=0;while i<600 {store8(data+i,(i*29+next)&255);i=i+1;}if esp_nvs_set_u8(h,"count",next) || esp_nvs_set_blob(h,"payload",data,600) || esp_nvs_commit(h) {return 8;}}nn_word("NVS COMMITTED ",next);
    let before=esp_nvs_calls;r=esp_wifi_station_init();nn_word("WIFI INIT ",r);if r {return 9;}nn_word("NVS VENDOR CALLS ",esp_nvs_calls-before);if esp_nvs_calls<=before || esp32_load32(esp_wifi_init_config+104)!=1 {return 10;}
    let scan=esp_sdk_calloc(1,64);if !scan {return 11;}esp32_store32(scan+12,1);esp32_store32(scan+24,120);r=esp32_call32(esp32_external("esp_wifi_scan_start"),scan,0,0,0,0,0,0,0);if r {nn_word("SCAN ERROR ",r);return 12;}
    let deadline=esp_sdk_now()+20000000;while !esp_radio_scan_done && esp_sdk_now()<deadline {esp_sdk_delay(1);}if !esp_radio_scan_done || esp_radio_scan_status {return 13;}
    r=esp32_call32(esp32_external("esp_wifi_scan_get_ap_num"),out+4,0,0,0,0,0,0,0);let count=load8(out+4)|(load8(out+5)<<8);nn_word("WIFI APS ",count);if r || !count {return 14;}
    kv_put32(out+8,608);if esp_nvs_get_blob(h,"payload",data,out+8) || kv_u32(out+8)!=600 {return 15;}let i=0;while i<600 {if load8(data+i)!=((i*29+next)&255) {return 16;}i=i+1;}
    nn_word("NVS TOTAL CALLS ",esp_nvs_calls);nn_word("NVS COMMITS ",esp_nvs_commits);nn_word("SDK FREE ",esp_sdk_heap_free());esp_uart_write("PASS: physical NVS persistence and vendor Wi-Fi passive scan\r\n");return 0;
}
fn main() {let r=nn_run();nn_word("NVS RESULT ",r);esp_uart_flush();return r;}
