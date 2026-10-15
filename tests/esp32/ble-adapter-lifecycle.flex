import "ble-adapter-runtime.flex";
import "../../lib/platform/esp32-gatt.flex";
fn main() {
    if esp_sdk_heap_init(0x3ffc8000,98304) || esp_sdk_task_init() {return 1;}esp_irq_enable();ba_wire=alloc(1100);ba_payload=alloc(128);let baseline=esp_sdk_heap_free();
    esp32_store32(esp32_external("test_ble_receive"),esp32_callback32(esp_bt_recv));esp32_store32(esp32_external("test_ble_ready"),esp32_callback32(esp_bt_send_ready));let previous=0;let round=0;
    while round<4 {
        if esp_bt_transport_init() || esp_ble_init(1) || esp_gatt_init(4,32,23) {return 2;}
        if esp_bt_controller_deinit()!= -16 || esp_ble_stop()!= -16 {return 3;}
        if esp_ble_advertise(ba_bytes("020106"),3,0,0,160) {return 4;}ba_conn(1);if esp_ble_poll() || bh_active!=1 {return 5;}let token=bh_generation;
        if token<=previous || bh_handle(token)!=64 || (previous && (bh_handle(previous)!= -107 || esp_ble_send(previous,4,"x",1)!= -107)) {return 6;}
        if round==3 {esp_bt_acl_dropped=1;if esp_ble_poll()!= -105 || esp_ble_state!=6 {return 10;}}if esp_gatt_deinit()!= -16 || esp_gatt_stop() || esp_gatt_stop() {return 7;}
        if esp_ble_state || esp_gatt_state || esp_bt_host_active || eb_work || eg_workspace || eb_owner || bh_work || bh_links || bh_active || bh_message_data || bh_packet || ga_work || ga_links || ga_event_data || ga_packet || esp_bt_rx || esp_sdk_heap_free()!=baseline {return 8;}
        if esp_ble_poll()!= -19 || bh_handle(token)!= -107 {return 9;}previous=token;round=round+1;
    }
    esp_uart_write("PASS: four BLE/GATT shutdown cycles, active-link teardown, stale-token rejection and exact heap recovery\r\n");esp_uart_flush();return 0;
}
