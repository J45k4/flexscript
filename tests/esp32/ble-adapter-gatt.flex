import "ble-adapter-runtime.flex";
import "../../lib/platform/esp32-gatt.flex";
global gg_value=0;
global gg_expected=0;
global gg_wire=0;
global gg_token=1;
fn gg_clear() {esp32_store32(esp32_external("test_ble_acl_log_size"),0);return 0;}
fn gg_flush() {
    let turns=0;let done=0;while turns<32 && !done {let r=esp_gatt_poll();if r {return r;}let c=ga_conn(gg_token);let index=bh_resolve(gg_token);let busy=esp_bt_event_count || esp_bt_acl_count || esp_bt_tx_inflight;if c {busy=busy || load64(c+24) || load64(c+32);}if index>=0 {let b=bh_slot(index);busy=busy || load64(b+64) || load64(b+96) || load64(b+112);}done=!busy;turns=turns+1;}if !done {return -110;}return 0;
}
fn gg_capture(expected,size) {
    let log=esp32_external("test_ble_acl_log");let bytes=esp32_load32(esp32_external("test_ble_acl_log_size"));let at=0;let used=0;let packets=0;
    while at<bytes {if at+2>bytes {return -1;}let n=ga_u16(log+at);at=at+2;if n<5 || at+n>bytes {return -2;}let p=log+at;let flags=ga_u16(p+1);let boundary=(flags>>12)&3;if load8(p)!=2 || (flags&4095)!=64 || (packets && boundary!=1) || (!packets && boundary) || ga_u16(p+3)!=n-5 || used+n-5>1028 {return -3;}nb_copy(gg_wire+used,p+5,n-5);used=used+n-5;at=at+n;packets=packets+1;}
    if used!=size+4 || ga_u16(gg_wire)!=size || ga_u16(gg_wire+2)!=4 || !nb_equal(gg_wire+4,expected,size) || (!packets || size>23 && packets<2) {return -4;}return 0;
}
fn gg_expect_hex(text) {let n=0;while load8(text+n*2) {store8(gg_expected+n,(nb_hex(load8(text+n*2))<<4)|nb_hex(load8(text+n*2+1)));n=n+1;}return gg_capture(gg_expected,n);}
fn gg_event(kind,handle,size) {if esp_gatt_event(gg_token)!=1 || ga_event_kind!=kind || ga_event_handle!=handle || ga_event_size!=size {return -1;}return esp_gatt_consume_event(gg_token);}
fn main() {
    if esp_sdk_heap_init(0x3ffc8000,98304) || esp_sdk_task_init() || esp_bt_transport_init() {return 1;}esp_irq_enable();ba_wire=alloc(1100);ba_payload=alloc(128);gg_value=alloc(512);gg_expected=alloc(512);gg_wire=alloc(1032);
    esp32_store32(esp32_external("test_ble_receive"),esp32_callback32(esp_bt_recv));esp32_store32(esp32_external("test_ble_ready"),esp32_callback32(esp_bt_send_ready));
    if esp_ble_init(1) || esp_gatt_init(24,2048,247) || ga_standard_services("Flexscript",10,0) || ga_service(ga_uuid16(0xff00),2,1)!=10 || ga_characteristic(ga_uuid16(0xff01),2,62,3,"abc",3,512)!=12 || esp_gatt_start() {return 2;}
    if esp_gatt_state!=2 || esp_gatt_start()!= -16 || esp_gatt_init(24,2048,247)!= -16 {return 3;}let owner=eb_owner;eb_owner=owner+8;if esp_gatt_poll()!= -16 || esp_gatt_set(12,"x",1)!= -16 {return 4;}eb_owner=owner;
    ba_conn(1);if esp_gatt_poll() || ga_find(1)<0 || ba_events() {return 5;}
    gg_clear();ba_acl(4,ba_bytes("02f700"),3);if gg_flush() || gg_expect_hex("03f700") || load64(ga_conn(1)+8)!=247 {return 6;}
    gg_clear();ba_acl(4,ba_bytes("100100ffff0028"),7);if gg_flush() || gg_expect_hex("11060100050000180600090001180a000d0000ff") {return 7;}
    gg_clear();ba_acl(4,ba_bytes("0a0300"),3);if gg_flush() || gg_expect_hex("0b466c6578736372697074") {return 8;}
    // A220-byte characteristic write crosses real HCI callback and host buffers.
    let i=0;while i<220 {store8(gg_value+i,(i*29+7)&255);i=i+1;}store8(gg_expected,0x12);ga_put16(gg_expected+1,12);nb_copy(gg_expected+3,gg_value,220);gg_clear();ba_acl(4,gg_expected,223);
    if gg_flush() || gg_expect_hex("13") || esp_gatt_value(12)!=1 || ga_value_size!=220 || !nb_equal(ga_value_data,gg_value,220) || esp_gatt_event(1)!=1 || ga_event_size!=220 || !nb_equal(ga_event_data,gg_value,220) {return 9;}
    // Pending copied application events apply backpressure without replacing
    // the first write snapshot or losing the next peer request.
    ba_acl(4,ba_bytes("120c007a"),4);if esp_gatt_poll() || !load64(bh_slot(0)+96) || !nb_equal(ga_event_data,gg_value,220) || esp_gatt_consume_event(1) || gg_flush() || gg_event(1,12,1) {return 10;}
    if esp_gatt_set(12,gg_value,220) {return 11;}gg_clear();ba_acl(4,ba_bytes("0a0c00"),3);if gg_flush() {return 12;}store8(gg_expected,0x0b);nb_copy(gg_expected+1,gg_value,220);if gg_capture(gg_expected,221) {return 13;}
    gg_clear();ba_acl(4,ba_bytes("120d000300"),5);if gg_flush() || gg_expect_hex("13") || gg_event(2,13,2) {return 14;}
    // A queued notification must never reach HCI after CCCD disable.
    if esp_gatt_subscriptions(1,12)!=3 || esp_gatt_notify(1,12,gg_value,220,0) {return 26;}gg_clear();ba_acl(4,ba_bytes("120d000000"),5);if gg_flush() || gg_expect_hex("13") || gg_event(2,13,2) || ga_cancelled_notifications!=1 || esp_gatt_subscriptions(1,12) {return 27;}
    gg_clear();ba_acl(4,ba_bytes("120d000300"),5);if gg_flush() || gg_expect_hex("13") || gg_event(2,13,2) {return 28;}
    gg_clear();if esp_gatt_notify(1,12,gg_value,220,0) || gg_flush() {return 15;}store8(gg_expected,0x1b);ga_put16(gg_expected+1,12);nb_copy(gg_expected+3,gg_value,220);if gg_capture(gg_expected,223) {return 16;}
    gg_clear();if esp_gatt_notify(1,12,gg_value,220,1) || gg_flush() {return 17;}store8(gg_expected,0x1d);if gg_capture(gg_expected,223) || !load64(ga_conn(1)+56) || esp_gatt_notify(1,12,gg_value,1,1)!= -11 {return 18;}ba_acl(4,ba_bytes("1e"),1);if gg_flush() || gg_event(3,12,0) {return 19;}
    // Prepare/execute changes the value atomically and exposes copied fragments.
    gg_clear();ba_acl(4,ba_bytes("160c0000006e6577"),8);if gg_flush() || gg_expect_hex("170c0000006e6577") || esp_gatt_value(12)!=1 || ga_value_size!=220 {return 20;}
    gg_clear();ba_acl(4,ba_bytes("1801"),2);if gg_flush() || gg_expect_hex("19") || esp_gatt_value(12)!=1 || ga_value_size!=3 || !nb_equal(ga_value_data,"new",3) || gg_event(1,12,3) {return 21;}
    ba_feed("04050400400013");if esp_gatt_poll() || ga_find(1)>=0 || esp_gatt_event(1)!= -107 || ba_events() {return 22;}ba_conn(1);gg_token=2;if esp_gatt_poll() || ga_find(2)<0 || ba_events() {return 23;}
    gg_clear();ba_acl(4,ba_bytes("0a0d00"),3);if gg_flush() || gg_expect_hex("0b0000") || esp_gatt_notify(2,12,"x",1,0)!= -13 {return 24;}
    gg_clear();ba_acl(4,ba_bytes("0a0c00"),3);if gg_flush() || gg_expect_hex("0b6e6577") || esp32_load32(esp32_external("test_ble_bad")) || esp_bt_event_dropped || esp_bt_acl_dropped || ga_cancelled_notifications!=1 {return 25;}
    esp_uart_write("PASS: GATT over actual BLE controller ABI, long ACL transfers, copied writes, CCCDs, notifications/indications and reconnect\r\n");return 0;
}
