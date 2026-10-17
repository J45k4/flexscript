import "../../lib/platform/esp32s3-xip.flex";
import "../../lib/platform/esp32s3-wifi.flex";
fn failure_app_irq(source) {return 0;}
fn failure_clean(baseline) {return !esp32_load32(esp32_external("s_wifi_api_lock")) && !esp32_load32(esp32_external("g_wifi_global_lock")) && !esp32_load32(esp32_external("eloop_data_lock")) && !esp_radio_owner && !esp_wifi_power_owned && !esp_wifi_initialized && !esp_wifi_vendor_initialized && !esp_wifi_vendor_running && !esp_wifi_supplicant && !esp_wifi_rx_ring && !esp_wifi_init_config && !esp_radio_osi && !esp_sdk_timer_task && !load64(esp_sdk_tasks+568) && load64(esp_sdk_tasks+536)==esp_sdk_tasks && esp_sdk_heap_free()==baseline && esp_irq_count==1 && esp_irq_handler(14)==esp32_callback(failure_app_irq);}
fn failure_configs() {
    let guard=alloc(216);let i=0;while i<216 {store8(guard+i,165);i=i+1;}let nvs=0;
    while nvs<2 {esp_radio_nvs_table=nvs;esp_radio_osi=305419896;if esp_wifi_build_init_config(guard+16) || esp32_call32(esp32_external("s3_wifi_check_init"),guard+16,305419896,nvs,0,0,0,0,0) {return 30;}
        i=0;while i<16 {if load8(guard+i)!=165 || load8(guard+176+i)!=165 {return 31;}i=i+1;}nvs=nvs+1;}
    esp_radio_nvs_table=0;esp_radio_osi=0;let auth=3;while auth<=6 {i=0;while i<216 {store8(guard+i,165);i=i+1;}
        if esp_wifi_station_config(guard+16,"testssid",8,"testpassword",12,auth) || esp32_call32(esp32_external("s3_wifi_check_station"),guard+16,auth,0,0,0,0,0,0) {return 32;}
        i=0;while i<16 {if load8(guard+i)!=165 || load8(guard+200+i)!=165 {return 33;}i=i+1;}auth=auth+3;}return 0;
}
fn failure_capacity(baseline,control) {
    let calls=esp32_load32(control+36);let delays=esp32_load32(control+116);let source=10;
    while source<42 {if source!=14 && esp_irq_attach(source,esp32_callback(failure_app_irq)) {return 34;}source=source+1;}
    let enable=esp32_irq_enabled();let table=esp_irq_table;let count=esp_irq_count;
    if count!=32 || esp_wifi_station_init()!= -12 || esp_wifi_cleanup_error || esp_wifi_power_owned || esp_radio_owner || esp_radio_osi || esp_wifi_rx_ring || esp_wifi_init_config || esp_sdk_heap_free()!=baseline || esp_irq_count!=count || esp_irq_table!=table || esp32_irq_enabled()!=enable || esp32_load32(control+36)!=calls || esp32_load32(control+116)!=delays {return 35;}
    esp_irq_detach(41);if esp_irq_count!=31 || esp_wifi_station_init()!= -12 || esp_wifi_cleanup_error || esp_wifi_power_owned || esp_radio_owner || esp_sdk_heap_free()!=baseline || esp_irq_count!=31 || esp32_irq_enabled()!=enable || esp32_load32(control+36)!=calls || esp32_load32(control+116)!=delays {return 36;}
    source=10;while source<41 {if esp_irq_handler(source)!=esp32_callback(failure_app_irq) {return 37;}if source!=14 {esp_irq_detach(source);}source=source+1;}
    if esp_irq_attach(2,esp32_callback(failure_app_irq)) || esp_wifi_station_init()!= -16 || esp_radio_owner || esp_wifi_power_owned || esp32_irq_enabled()!=enable || esp32_load32(control+36)!=calls || esp32_load32(control+116)!=delays {return 38;}esp_irq_detach(2);
    if !failure_clean(baseline) {return 39;}return 0;
}
fn failure_run() {
    if esp_sdk_heap_init(esp_sdk_heap_min(),esp_sdk_heap_max()-esp_sdk_heap_min()) || esp_sdk_task_init() || esp_irq_attach(14,esp32_callback(failure_app_irq)) {return 1;}esp_irq_enable();let control=esp32_external("wifi_lifecycle_oracle");let baseline=esp_sdk_heap_free();let check=failure_configs();if check {return check;}check=failure_capacity(baseline,control);if check {return check;}if esp_irq_attach(0,esp32_callback(failure_app_irq)) || esp_wifi_station_init()!= -16 || esp_sdk_heap_free()!=baseline || esp_irq_handler(0)!=esp32_callback(failure_app_irq) {return 14;}esp_irq_detach(0);esp_adc_busy=1;if esp_wifi_station_init()!= -16 || esp_radio_owner || esp32_load32(control+36) || esp_sdk_heap_free()!=baseline {return 15;}esp_adc_busy=0;if !failure_clean(baseline) {return 16;}let stage=1;
    while stage<=7 {esp32_store32(control,stage);let r=esp_wifi_station_init();if r!=700+stage || esp_wifi_cleanup_error || !failure_clean(baseline) {esp_uart_write("FAILED INIT STAGE ");esp_uart_hex(stage);esp_uart_hex(r);return 2;}stage=stage+1;}
    stage=8;while stage<=10 {esp32_store32(control,0);if esp_wifi_station_init() {return 3;}let held=esp_sdk_heap_free();let ring=esp_wifi_rx_ring;esp32_store32(control,stage);esp_wifi_want_link=1;esp_wifi_retry_at=1;
        if esp_wifi_station_deinit()!=700+stage || !esp_wifi_initialized || esp_radio_owner!=1 || esp_wifi_rx_ring!=ring || esp_wifi_want_link || esp_wifi_retry_at || esp_sdk_heap_free()!=held {return 4;}
        if stage==8 && !esp_wifi_vendor_running {return 5;}if stage==9 && !esp_wifi_vendor_initialized {return 6;}if stage==10 && (esp_wifi_vendor_initialized || !esp_wifi_supplicant) {return 7;}
        esp32_store32(control,0);if esp_wifi_station_deinit() || esp_wifi_station_deinit() || !failure_clean(baseline) {return 8;}stage=stage+1;
    }
    esp32_store32(control,7);esp32_store32(control+4,8);if esp_wifi_station_init()!=707 || esp_wifi_cleanup_error!=708 || esp_radio_owner!=1 || !esp_wifi_rx_ring {return 9;}esp32_store32(control,0);esp32_store32(control+4,0);if esp_wifi_station_deinit() || !failure_clean(baseline) {return 10;}
    let remaining=1000;while remaining<16000 {let held=esp_sdk_malloc(baseline-remaining);if !held {return 11;}let before=esp_sdk_heap_free();if esp_wifi_station_init()!= -12 || esp_wifi_cleanup_error || esp_sdk_heap_free()!=before {return 12;}esp_sdk_free(held);if !failure_clean(baseline) {return 13;}if remaining==1000 {remaining=7000;}else if remaining==7000 {remaining=15100;}else {remaining=16000;}}
    esp_uart_write("PASS: S3 typed config/canaries, full/near-full IRQ table, foreign PWR, seven Wi-Fi init failures, stop/deinit/supplicant retries, failed rollback and three allocation failures\r\n");esp_uart_flush();return 0;
}

fn main() {let r=failure_run();if r {esp_uart_write("S3 WIFI FAIL ");esp_uart_hex(r);esp_uart_write("\r\n");esp_uart_flush();}return r;}
