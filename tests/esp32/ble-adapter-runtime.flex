import "../../lib/platform/esp32-xip.flex";
import "../../lib/platform/esp32-ble.flex";
global ba_wire=0;
global ba_payload=0;
global ba_grant_error=0;
fn ba_bytes(text) {let n=0;while load8(text+n*2) {store8(ba_payload+n,(nb_hex(load8(text+n*2))<<4)|nb_hex(load8(text+n*2+1)));n=n+1;}return ba_payload;}
fn ba_feed(text) {let n=0;while load8(text+n*2) {store8(ba_wire+n,(nb_hex(load8(text+n*2))<<4)|nb_hex(load8(text+n*2+1)));n=n+1;}return esp32_call32(esp32_callback32(esp_bt_recv),ba_wire,n,0,0,0,0,0,0);}
fn ba_grant(a,b,c,d,e,f,g,h) {esp_sdk_delay(5);if esp32_load32(esp32_external("test_ble_count")) || esp_bt_cmd_credits {ba_grant_error=1;}ba_feed("040e03010000");return 0;}
fn ba_conn(role) {ba_feed("043e1301004000010001020304050618000000900100");let p=esp_bt_event_ring+((esp_bt_event_head+esp_bt_event_count-1)%8)*528+16;store8(p+7,role);return 0;}
fn ba_acl(cid,body,size) {store8(ba_wire,2);bh_put16(ba_wire+1,0x2040);bh_put16(ba_wire+3,size+4);bh_put16(ba_wire+5,size);bh_put16(ba_wire+7,cid);nb_copy(ba_wire+9,body,size);return esp32_call32(esp32_callback32(esp_bt_recv),ba_wire,size+9,0,0,0,0,0,0);}
fn ba_events() {while esp_ble_event()==1 {if esp_ble_consume_event() {return -1;}}return 0;}
fn ba_op() {let count=esp32_load32(esp32_external("test_ble_count"));let ops=esp32_external("test_ble_ops");while count && esp32_load32(ops+(count-1)*4)==0x0c35 {count=count-1;}if !count {return 0;}return esp32_load32(ops+(count-1)*4);}
fn ba_run(shared,flow) {
    if esp_sdk_heap_init(0x3ffc8000,98304) || esp_sdk_task_init() || esp_bt_transport_init() {return 1;}esp_irq_enable();ba_wire=alloc(1100);ba_payload=alloc(128);
    esp32_store32(esp32_external("test_ble_receive"),esp32_callback32(esp_bt_recv));esp32_store32(esp32_external("test_ble_ready"),esp32_callback32(esp_bt_send_ready));esp32_store32(esp32_external("test_ble_shared"),shared);esp32_store32(esp32_external("test_ble_flow"),flow);
    // Zero command credits must actually wait for a controller grant. A NOP
    // Command Complete has no Status byte and must still replenish credits.
    ba_feed("040e03000000");if esp_bt_hci_next_event()!=6 || esp_bt_cmd_credits {return 27;}let task=esp_sdk_task_create(esp32_callback32(ba_grant),0,4096,1);if !task || esp_bt_hci_command(0x0c03,0,0) || ba_grant_error || esp_bt_cmd_credits!=1 || esp_bt_hci_next_event()!=6 || esp_sdk_task_reap(task) {return 2;}
    if esp_ble_init(0)!= -22 || esp_ble_init(5)!= -22 || esp_ble_init(1) || esp_ble_init(1)!= -16 || esp_ble_state!=1 || bh_links!=1 || bh_host_flow!=flow || load8(esp_ble_address)!=1 || load8(esp_ble_address+5)!=6 {return 3;}
    let expected_mtu=27;let expected_buffers=2;if shared {expected_mtu=64;expected_buffers=3;}if bh_acl_mtu!=expected_mtu || bh_free!=expected_buffers {return 4;}
    let owner=eb_owner;eb_owner=owner+8;if esp_ble_poll()!= -16 || esp_ble_send(1,4,"x",1)!= -16 || esp_ble_event()!= -16 {return 5;}eb_owner=owner;
    let count=esp32_load32(esp32_external("test_ble_count"));if esp_ble_advertise(0,1,0,0,160)!= -22 || esp_ble_advertise("x",32,0,0,160)!= -22 || esp_ble_connect("123456",2,24,40,0,400,1000)!= -22 || esp_ble_connect("123456",0,40,24,0,400,1000)!= -22 || esp32_load32(esp32_external("test_ble_count"))!=count {return 6;}
    if esp_ble_advertise(ba_bytes("020106"),3,0,0,160) || esp_ble_advertising!=1 || ba_op()!=0x200a || esp_ble_connect("123456",0,24,40,0,400,1000)!= -16 || esp_ble_advertise_enable(0) || esp_ble_advertising {return 7;}
    if esp_ble_connect("123456",1,24,40,0,400,1000) || esp_ble_connecting!=1 || ba_op()!=0x200d || esp_ble_cancel() || esp_ble_connecting!=2 || esp_ble_connect_error!= -125 || ba_op()!=0x200e {return 8;}
    ba_feed("043e1301020000000000000000000000000000000000");if esp_ble_poll() || esp_ble_connecting || esp_ble_connect_error!= -125 || bh_active || ba_events() {return 9;}
    if esp_ble_advertise_enable(1) {return 10;}ba_conn(1);if esp_ble_poll() || esp_ble_advertising || bh_active!=1 || bh_handle(1)!=64 || ba_events() {return 11;}
    ba_feed("043e0d05400001020304050607080100");if esp_ble_poll() || ba_op()!=0x201b || ba_events() {return 12;}
    ba_feed("043e0b0640001800280000009001");if esp_ble_poll() || ba_op()!=0x2020 || ba_events() {return 13;}
    ba_feed("043e0b0640002800180000009001");if esp_ble_poll() || ba_op()!=0x2021 || ba_events() {return 14;}
    // Binary application traffic is separate from adapter-owned signaling.
    ba_acl(4,"abc",3);if esp_ble_poll() || esp_ble_message(1)!=1 || bh_message_size!=3 || !nb_equal(bh_message_data,"abc",3) || bh_message_encrypted || esp_ble_consume(1) {return 15;}
    let before=esp_sdk_heap_free();if esp_ble_send(1,5,"x",1)!= -22 || esp_ble_send(1,4,"abc",3) || esp_ble_send(1,4,"x",1)!= -11 || esp_ble_poll() || !esp32_load32(esp32_external("test_ble_acl_count")) || esp_ble_poll() || bh_free!=expected_buffers || bh_outstanding(1) || esp_sdk_heap_free()!=before {return 16;}
    // Peripheral rejects a Central's invalid-direction parameter update request.
    ba_acl(5,ba_bytes("120708001800280000009001"),12);if esp_ble_poll() || esp_ble_poll() {return 17;}let sent=esp32_external("test_ble_acl");if load8(sent+9)!=1 || load8(sent+10)!=7 || bh_u16(sent+11)!=2 || bh_u16(sent+13) || esp_ble_message(1)!=0 {return 18;}
    // An unread application PDU retains the next ACL frame ahead of a queued
    // disconnect. Explicit consumption restores progress without reordering.
    ba_acl(4,"old",3);if esp_ble_poll() {return 19;}ba_acl(4,"next",4);ba_feed("04050400400013");ba_conn(0);
    if esp_ble_poll() || !esp_bt_acl_count || bh_handle(1)!=64 || bh_handle(2)!= -107 || esp_ble_message(1)!=1 || !nb_equal(bh_message_data,"old",3) || esp_ble_consume(1) || esp_ble_poll() || bh_handle(1)!= -107 || bh_handle(2)!=64 || esp_ble_message(2)!=0 || esp_ble_consume(1)!= -107 || ba_events() {return 20;}
    // Central accepts a valid request and issues the independent HCI update.
    ba_acl(5,ba_bytes("120808001800280000009001"),12);if esp_ble_poll() || esp_ble_poll() || load8(sent+9)!=0x13 || load8(sent+10)!=8 || bh_u16(sent+13) {return 21;}
    // Unknown signaling receives Command Reject; malformed signaling closes
    // only that connection, then the actual disconnection invalidates its ID.
    ba_acl(5,ba_bytes("7f090000"),4);if esp_ble_poll() || esp_ble_poll() || load8(sent+9)!=1 || load8(sent+10)!=9 {return 22;}
    ba_acl(5,ba_bytes("12010900"),4);if esp_ble_poll() || ba_op()!=0x0406 || !load64(bh_slot(0)+208) || esp_ble_send(2,4,"x",1)!= -107 || esp_ble_update(2,24,40,0,400)!= -107 || ba_events() {return 23;}ba_feed("04050400400013");if esp_ble_poll() || bh_active || ba_events() {return 24;}
    // An abandoned receive view has a bounded deadline. Expiry initiates a
    // real disconnect and lets the queued data/disconnect sequence drain.
    ba_conn(1);if esp_ble_poll() || ba_events() {return 28;}ba_acl(4,"held",4);if esp_ble_poll() {return 29;}ba_acl(4,"blocked",7);if esp_ble_poll() || !eb_blocked_sequence {return 30;}eb_blocked_deadline=0;
    if esp_ble_poll() || ba_op()!=0x0406 || esp_ble_send(3,4,"x",1)!= -107 || ba_events() {return 31;}ba_feed("04050400400013");if esp_ble_poll() || bh_active || bh_handle(3)!= -107 || esp_bt_acl_count || ba_events() {return 32;}
    // A connection completing after a timed-out cancel is immediately closed;
    // it cannot silently become an application connection after the deadline.
    if esp_ble_connect("123456",0,24,40,0,400,1000) {return 33;}eb_connect_deadline=0;if esp_ble_poll() || esp_ble_connecting!=2 || esp_ble_connect_error!= -110 || ba_op()!=0x200e {return 34;}
    ba_conn(0);if esp_ble_poll() || esp_ble_connecting || esp_ble_connect_error!= -110 || ba_op()!=0x0406 || esp_ble_send(4,4,"x",1)!= -107 || ba_events() {return 35;}ba_feed("04050400400013");if esp_ble_poll() || bh_active || ba_events() {return 36;}
    if esp32_load32(esp32_external("test_ble_bad")) || esp_bt_event_dropped || esp_bt_acl_dropped || bh_error || esp_ble_state!=1 || esp_ble_error {return 25;}
    // Packet loss requires recovery; a stateful host must not continue after it.
    if flow {let credits=esp_bt_cmd_credits;ba_feed("040e0400350c12");if esp_bt_cmd_credits!=credits || esp_ble_poll()!= -4114 || esp_ble_state!=6 || esp_ble_send(2,4,"x",1)!= -4114 {return 26;}}else {esp_bt_acl_dropped=1;if esp_ble_poll()!= -105 || esp_ble_state!=6 || esp_ble_send(2,4,"x",1)!= -105 {return 37;}}
    esp_uart_write("PASS: BLE adapter buffers/flow, command credits, advertising/connect/cancel, signaling, ownership and ordered ACL\r\n");return 0;
}
