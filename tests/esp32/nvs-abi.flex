import "../../lib/platform/esp32-nvs.flex";
fn main() {
    if esp_sdk_heap_init(0x3ffc8000,98304) || esp_sdk_task_init() {return 1;}let free=esp_sdk_heap_free();if esp_nvs_init(0x3e0000,4096,1) {return 2;}
    let osi=esp32_external("nvs_osi_fixture");esp32_store32(osi,9);esp32_store32(osi+272,0x12345678);esp32_store32(osi+324,0xabcdefff);esp_radio_osi=osi;esp_radio_nvs_apply();
    let test=esp32_external("nvs_fixture_run");let result=esp32_call32(test,0,0,0,0,0,0,0,0);if result {esp_uart_hex(result);return 3;}if esp_nvs_reload() {return 4;}
    result=esp32_call32(test,1,0,0,0,0,0,0,0);if result {esp_uart_hex(result);return 5;}if esp_nvs_reload() {return 6;}result=esp32_call32(test,2,0,0,0,0,0,0,0);if result {esp_uart_hex(result);return 7;}
    if esp_nvs_release()!= -16 {return 8;}esp_radio_osi=0;if esp_nvs_release() || esp_sdk_heap_free()!=free || esp_radio_nvs_table {return 9;}result=esp32_call32(test,3,0,0,0,0,0,0,0);if result {return 10;}
    let raw=esp_sdk_calloc(1,kv_size(4096));let core=esp_sdk_calloc(1,nv_size(2));if !raw || !core || esp_settings_init(0x3e0000,4096,raw,kv_size(4096),80000000) || nv_init(core,nv_size(2),2) {return 11;}
    if esp_nvs_release() || kv_work!=raw || !kv_mounted || nv_work!=core || !nv_ready || esp_settings_bank!=4096 {esp_uart_write("FAIL: idempotent NVS release cleared unrelated settings owner\r\n");return 12;}
    let remaining=esp_sdk_heap_free();let sequence=nv_next_token;esp_radio_nvs_table=raw;
    if esp_nvs_init(0,4096,0)>=0 || !env_workspace || esp_nvs_release() || kv_work!=raw || !kv_mounted || nv_work!=core || !nv_ready || esp_radio_nvs_table!=raw || nv_next_token!=sequence || esp_sdk_heap_free()!=remaining {return 13;}
    esp_radio_nvs_table=0;esp_sdk_free(raw);esp_sdk_free(core);
    esp_uart_write("PASS: windowed C NVS callbacks, namespace/types/blob lengths, commit/reload and release\r\n");esp_uart_flush();return 0;
}
