import "../../lib/platform/esp32-xip.flex";
import "../../lib/platform/esp32-bluetooth.flex";
import "../../lib/net/ble-host.flex";
global test_last_sequence=0;
fn test_receive(packet,text) {let n=0;while load8(text+n*2) {store8(packet+n,(nb_hex(load8(text+n*2))<<4)|nb_hex(load8(text+n*2+1)));n=n+1;}return esp32_call32(esp32_callback32(esp_bt_recv),packet,n,0,0,0,0,0,0);}
fn test_drain() {
    let count=0;while esp_bt_hci_peek_packet() {
        if esp_bt_packet_sequence<=test_last_sequence || esp_bt_packet_kind!=load8(esp_bt_packet) {return -1;}
        test_last_sequence=esp_bt_packet_sequence;if bh_input(esp_bt_packet,esp_bt_packet_size,test_last_sequence)!=1 {return -2;}
        if esp_bt_hci_consume_packet() || esp_bt_hci_consume_packet()!= -16 {return -3;}count=count+1;
    }return count;
}
fn main() {
    if esp_sdk_heap_init(0x3ffc8000,98304) || esp_sdk_task_init() {return 1;}
    let occupied=esp_sdk_malloc(94100);let remaining=esp_sdk_heap_free();if !occupied || esp_bt_transport_init()!= -12 || esp_bt_rx || esp_sdk_heap_free()!=remaining {return 12;}esp_sdk_free(occupied);
    if esp_bt_transport_init() {return 13;}esp_bt_tx_inflight=1;esp_bt_tx_ready=0;esp_bt_send_ready(0,0,0,0,0,0,0,0);if esp_bt_tx_inflight || esp_bt_tx_ready!=1 {return 14;}
    let before=esp_sdk_heap_free();let packet=alloc(1100);let callback=esp32_callback32(esp_bt_recv);esp_irq_enable();
    // Fill and overflow the bounded event ring. Every callback acknowledges the
    // consumed packet, with no per-packet allocation or controller backpressure.
    let i=0;while i<16 {store8(packet,4);store8(packet+1,0x3e);store8(packet+2,1);store8(packet+3,i);if esp32_call32(callback,packet,4,0,0,0,0,0,0) {return 2;}i=i+1;}
    if esp_bt_event_count!=8 || esp_bt_event_dropped!=8 || esp_sdk_heap_free()!=before {return 3;}
    // A full async ring must not prevent the in-flight command from completing.
    esp_bt_cmd_busy=1;esp_bt_cmd_opcode=0x1001;store8(packet,4);store8(packet+1,14);store8(packet+2,4);store8(packet+3,1);store8(packet+4,1);store8(packet+5,16);store8(packet+6,0);
    if esp32_call32(callback,packet,7,0,0,0,0,0,0) || esp_bt_cmd_size!=7 || load8(esp_bt_cmd+4)!=1 || esp_bt_event_count!=8 || esp_bt_hci_next_event() {return 4;}
    esp_bt_cmd_busy=0;i=0;while i<8 {if esp_bt_hci_next_event()!=4 || load8(esp_bt_rx+3)!=i {return 5;}i=i+1;}if esp_bt_hci_next_event() {return 6;}
    // Exercise wrap and ensure unrelated command events do not steal a response.
    i=0;while i<24 {store8(packet+1,0x3e);store8(packet+2,1);store8(packet+3,i);if esp32_call32(callback,packet,4,0,0,0,0,0,0) || esp_bt_hci_next_event()!=4 || load8(esp_bt_rx+3)!=i {return 7;}i=i+1;}
    esp_bt_cmd_busy=1;esp_bt_cmd_size=0;store8(packet+1,14);store8(packet+2,4);store8(packet+4,2);if esp32_call32(callback,packet,7,0,0,0,0,0,0) || esp_bt_cmd_size || esp_bt_event_count!=1 {return 8;}
    store8(packet+1,15);store8(packet+3,0);store8(packet+4,1);store8(packet+5,1);store8(packet+6,16);if esp32_call32(callback,packet,7,0,0,0,0,0,0) || esp_bt_cmd_size!=7 {return 9;}
    esp_bt_cmd_busy=0;if esp_bt_hci_next_event()!=7 || load8(esp_bt_rx+4)!=2 {return 10;}
    if esp32_call32(callback,0,513,0,0,0,0,0,0) || esp32_call32(callback,0,4,0,0,0,0,0,0) || esp_bt_event_dropped!=10 || esp_sdk_heap_free()!=before {return 11;}
    // ACL capacity is independent of control traffic and includes1024 data bytes.
    store8(packet,2);store8(packet+1,64);store8(packet+2,32);store8(packet+3,0);store8(packet+4,4);i=0;while i<1024 {store8(packet+5+i,i);i=i+1;}
    i=0;while i<5 {if esp32_call32(callback,packet,1029,0,0,0,0,0,0) {return 15;}i=i+1;}if esp_bt_acl_count!=4 || esp_bt_acl_dropped!=1 || esp_bt_event_count {return 16;}
    if esp_bt_hci_peek_acl()!=1029 || load8(esp_bt_acl_packet+1028)!=255 {return 17;}let held=esp_bt_acl_packet;
    store8(packet,4);store8(packet+1,62);store8(packet+2,1);store8(packet+3,170);esp32_call32(callback,packet,4,0,0,0,0,0,0);
    esp_bt_cmd_busy=1;esp_bt_cmd_opcode=0x1001;esp_bt_cmd_size=0;store8(packet+1,14);store8(packet+2,4);store8(packet+3,1);store8(packet+4,1);store8(packet+5,16);store8(packet+6,0);esp32_call32(callback,packet,7,0,0,0,0,0,0);
    if esp_bt_cmd_size!=7 || esp_bt_event_count!=1 || esp_bt_acl_count!=4 || esp_bt_hci_next_event() {return 18;}esp_bt_cmd_busy=0;
    if esp_bt_hci_next_event()!=4 || load8(esp_bt_rx+3)!=170 || esp_bt_acl_packet!=held || load8(held+1028)!=255 {return 19;}
    i=0;while i<4 {if esp_bt_hci_peek_acl()!=1029 || load8(esp_bt_acl_packet+5)!=0 || load8(esp_bt_acl_packet+1028)!=255 || esp_bt_hci_consume_acl() {return 20;}i=i+1;}if esp_bt_hci_peek_acl() || esp_bt_hci_consume_acl()!= -11 {return 21;}
    i=0;while i<16 {store8(packet,2);store8(packet+1,64);store8(packet+2,32);store8(packet+3,3);store8(packet+4,0);store8(packet+5,i);store8(packet+6,0);store8(packet+7,0);if esp32_call32(callback,packet,8,0,0,0,0,0,0) || esp_bt_hci_peek_acl()!=8 || load8(esp_bt_acl_packet+5)!=i || esp_bt_hci_consume_acl() {return 22;}i=i+1;}
    store8(packet+3,4);if esp32_call32(callback,packet,8,0,0,0,0,0,0) || esp_bt_acl_dropped!=2 || esp_bt_acl_count {return 23;}
    store8(packet,4);store8(packet+1,62);store8(packet+2,5);if esp32_call32(callback,packet,4,0,0,0,0,0,0) || esp_bt_event_dropped!=11 || esp_bt_event_count {return 24;}
    if esp32_call32(callback,packet,1033,0,0,0,0,0,0) || esp_bt_event_dropped!=12 {return 25;}
    // The controller receives transport-owned storage, never a borrowed caller buffer.
    let available=esp32_external("test_vhci_available");let count=esp32_external("test_vhci_count");let record=esp32_external("test_vhci_record");let pointer=esp32_external("test_vhci_pointer");let size=esp32_external("test_vhci_size");
    store8(packet,2);store8(packet+1,64);store8(packet+2,0);store8(packet+3,0);store8(packet+4,4);i=0;while i<1024 {store8(packet+5+i,i);i=i+1;}
    if esp_bt_hci_send_packet(packet,1029) || esp32_load32(count)!=1 || esp32_load32(size)!=1029 || esp32_load32(pointer)!=esp_bt_tx || !esp_bt_tx_inflight || esp32_load32(record)!=0x13572468 || esp32_load32(record+1036)!=0x24681357 {return 26;}
    store8(packet+5,42);if load8(esp_bt_tx+5)!=0 || esp_bt_hci_send_packet(packet,1029)!= -11 || esp32_load32(count)!=1 || load8(esp_bt_tx+5)!=0 {return 27;}
    esp_bt_send_ready(0,0,0,0,0,0,0,0);esp32_store32(available,0);if esp_bt_hci_send_packet(packet,1029)!= -11 || esp32_load32(count)!=1 || load8(esp_bt_tx+5)!=0 {return 28;}esp32_store32(available,1);esp_bt_cmd_busy=1;if esp_bt_hci_send_packet(packet,1029)!= -11 {return 29;}esp_bt_cmd_busy=0;
    if esp_bt_hci_send_packet(packet,1029) || esp32_load32(count)!=2 || load8(esp_bt_tx+5)!=42 {return 30;}esp_bt_send_ready(0,0,0,0,0,0,0,0);
    store8(packet,1);store8(packet+1,0x35);store8(packet+2,0x0c);store8(packet+3,5);store8(packet+4,1);store8(packet+5,64);store8(packet+6,0);store8(packet+7,2);store8(packet+8,0);
    esp_bt_cmd_credits=0;esp_bt_cmd_busy=1;esp_bt_cmd_opcode=0x1001;esp_bt_cmd_size=0;if esp_bt_hci_send_packet(packet,9) || esp32_load32(count)!=3 || esp32_load32(size)!=9 || !esp_bt_cmd_busy || esp_bt_cmd_size || esp_bt_cmd_credits {return 31;}store8(packet,4);store8(packet+1,14);store8(packet+2,4);store8(packet+3,1);store8(packet+4,1);store8(packet+5,16);store8(packet+6,0);if esp32_call32(callback,packet,7,0,0,0,0,0,0) || esp_bt_cmd_size!=7 || esp_bt_event_count {return 33;}esp_bt_cmd_busy=0;esp_bt_send_ready(0,0,0,0,0,0,0,0);store8(packet,1);store8(packet+2,0x0c);store8(packet+3,5);store8(packet+4,1);
    store8(packet+1,3);if esp_bt_hci_send_packet(packet,9)!= -22 || esp32_load32(count)!=3 || esp_bt_hci_send_packet(0,9)!= -22 || esp_bt_hci_command(65536,0,0)!= -22 || esp_sdk_heap_free()!=before {return 32;}

    // Cross-queue order is semantic: an encryption event cannot overtake the
    // first ACL fragment, and recycled handles cannot inherit old peer data.
    let work=esp_sdk_malloc(6416);if !work || bh_init(work,6416,1) {return 34;}
    if test_receive(packet,"043e1301004000010001020304050618000000900100") || test_receive(packet,"02402005000300040061") || test_receive(packet,"04080400400001") || test_receive(packet,"02401002006263") {return 35;}
    if esp_bt_event_count!=2 || esp_bt_acl_count!=2 || test_drain()!=4 || bh_active!=1 || bh_handle(1)!=64 || bh_message(1)!=1 || bh_message_size!=3 || !nb_equal(bh_message_data,"abc",3) || bh_message_encrypted || load64(bh_slot(0)+56)!=1 || bh_consume(1) {return 36;}
    if test_receive(packet,"0240200700030004006f6c64") || test_receive(packet,"04050400400013") || test_receive(packet,"043e1301004000010001020304050618000000900100") || test_receive(packet,"0240200700030004006e6577") {return 37;}
    if test_drain()!=4 || bh_active!=1 || bh_handle(1)!= -107 || bh_handle(2)!=64 || bh_message(2)!=1 || bh_message_size!=3 || !nb_equal(bh_message_data,"new",3) || bh_message_encrypted || bh_consume(2) {return 38;}
    // Repeated peek retains the view; stale/mixed-API consumption cannot pop
    // the next packet, even after the physical ring slot wraps around.
    if test_receive(packet,"043e0202aa") || esp_bt_hci_peek_packet()!=5 {return 39;}let view=esp_bt_packet;let sequence=esp_bt_packet_sequence;
    if esp_bt_hci_peek_packet()!=5 || esp_bt_packet!=view || esp_bt_packet_sequence!=sequence || esp_bt_hci_next_event()!=5 || esp_bt_hci_consume_packet()!= -16 {return 40;}
    i=0;while i<8 {if test_receive(packet,"043e0202aa") {return 41;}if i<7 && esp_bt_hci_next_event()!=5 {return 42;}i=i+1;}
    if esp_bt_hci_consume_packet()!= -16 || esp_bt_event_count!=1 || esp_bt_hci_peek_packet()!=5 || esp_bt_packet_sequence<=sequence || esp_bt_hci_consume_packet() || esp_bt_hci_peek_packet() || esp_bt_packet || esp_bt_packet_kind {return 43;}
    // Command responses retain their receipt sequence without stealing a
    // queued control or ACL slot, even when both async rings are occupied.
    test_receive(packet,"043e0202aa");test_receive(packet,"024020040000000400");esp_bt_cmd_busy=1;esp_bt_cmd_size=0;esp_bt_cmd_opcode=0x1001;test_receive(packet,"040e0401011000");
    if esp_bt_cmd_size!=7 || esp_bt_event_count!=1 || esp_bt_acl_count!=1 || esp_bt_hci_peek_packet()!=5 || esp_bt_packet_kind!=4 || esp_bt_packet_sequence>=esp_bt_cmd_sequence || esp_bt_hci_consume_packet() || esp_bt_hci_peek_packet()!=9 || esp_bt_packet_kind!=2 || esp_bt_packet_sequence>=esp_bt_cmd_sequence || esp_bt_hci_consume_packet() {return 44;}esp_bt_cmd_busy=0;
    // An error response to the special host-completed command is asynchronous;
    // its ncmd field neither steals a response nor changes ordinary credits.
    esp_bt_cmd_credits=2;esp_bt_cmd_busy=1;esp_bt_cmd_opcode=0x1001;esp_bt_cmd_size=0;test_receive(packet,"040e0400350c12");if esp_bt_cmd_credits!=2 || esp_bt_cmd_size || esp_bt_event_count!=1 || esp_bt_hci_next_event() {return 46;}esp_bt_cmd_busy=0;if esp_bt_hci_next_event()!=7 || load8(esp_bt_rx+6)!=0x12 {return 47;}
    esp_sdk_free(work);if esp_sdk_heap_free()!=before {return 45;}
    esp_uart_write("PASS: bounded ordered VHCI control/ACL, retained TX ownership, encryption snapshots and recycled handles\r\n");return 0;
}
