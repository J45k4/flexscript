import "../../lib/platform/esp32-xip.flex";
import "../../lib/platform/esp32-radio-clock.flex";
import "../../lib/platform/esp32-ble.flex";
// Independent-peer ACL transport probe. Its two ATT test handles are a fixture,
// not the GATT service/discovery implementation tracked under T138.
global bp_value=0;
global bp_reply=0;
global bp_size=180;
global bp_connection=0;
global bp_mtu=23;
global bp_notify=0;
global bp_connections=0;
global bp_disconnects=0;
global bp_reads=0;
global bp_writes=0;
global bp_notifications=0;
fn bp_word(label,n) {esp_uart_write(label);esp_uart_hex(n);esp_uart_write("\r\n");return n;}
fn bp_request() {
    if !bp_connection || esp_ble_message(bp_connection)!=1 {return 0;}let in=bh_message_data;let n=bh_message_size;let cid=bh_message_cid;let out=bp_reply;
    if cid!=4 || !n {return esp_ble_consume(bp_connection);}let op=load8(in);let handle=0;if n>=3 {handle=bh_u16(in+1);}let size=5;let read=0;let write=0;let notify= -1;let mtu=0;
    store8(out,1);store8(out+1,op);bh_put16(out+2,handle);store8(out+4,0x0a);
    if op&0x40 {return esp_ble_consume(bp_connection);}
    if n>bp_mtu {store8(out+4,4);}
    else if op==2 && n==3 {let requested=bh_u16(in+1);if requested>=23 {store8(out,3);bh_put16(out+1,247);size=3;mtu=requested;if mtu>247 {mtu=247;}}else {store8(out+4,4);}}
    else if op==0x0a && n==3 && handle==1 {store8(out,0x0b);let length=bp_size;if length>bp_mtu-1 {length=bp_mtu-1;}nb_copy(out+1,bp_value,length);size=length+1;read=1;}
    else if op==0x12 && n>=3 && handle==1 {if n-3<=240 {store8(out,0x13);size=1;write=1;}else {store8(out+4,0x0d);}}
    else if op==0x12 && n==5 && handle==2 {let value=bh_u16(in+3);if value<=1 {store8(out,0x13);size=1;notify=value;}else {store8(out+4,0x13);}}
    let r=esp_ble_send(bp_connection,4,out,size);if r== -11 {return 0;}if r {return r;}
    if mtu {bp_mtu=mtu;}if read {bp_reads=bp_reads+1;}if write {bp_size=n-3;nb_copy(bp_value,in+3,bp_size);bp_writes=bp_writes+1;}if notify>=0 {bp_notify=notify;}
    return esp_ble_consume(bp_connection);
}
fn main() {
    esp_uart_write("Flexscript BLE connection/ACL probe\r\n");esp_radio_clock_init();esp_radio_cpu160();if esp_sdk_heap_init(0x3ffc8000,98304) || esp_sdk_task_init() {return 1;}esp_irq_enable();let r=esp_ble_start(1);if bp_word("BLE init ",r) {return 2;}
    bp_word("BLE default TX level ",esp32_call32(esp32_external("ble_txpwr_get"),11,0,0,0,0,0,0,0));bp_word("BLE advertising TX level ",esp32_call32(esp32_external("ble_txpwr_get"),9,0,0,0,0,0,0,0));
    let address=0;let i=0;while i<6 {address=address|(load8(esp_ble_address+i)<<(i*8));i=i+1;}bp_word("BLE address ",address);bp_word("BLE ACL mtu ",bh_acl_mtu);bp_word("BLE ACL buffers ",bh_buffers);bp_word("BLE host flow ",bh_host_flow);bp_word("BLE SDK free ",esp_sdk_heap_free());
    bp_value=alloc(256);bp_reply=alloc(256);let adv=alloc(32);if bp_value<=0 || bp_reply<=0 || adv<=0 {return 3;}i=0;while i<bp_size {store8(bp_value+i,(i*17+3)&255);i=i+1;}
    nb_zero(adv,32);store8(adv,2);store8(adv+1,1);store8(adv+2,6);store8(adv+3,14);store8(adv+4,9);nb_copy(adv+5,"FlexscriptACL",13);if bp_word("BLE advertise ",esp_ble_advertise(adv,18,0,0,160)) {return 4;}esp_uart_write("BLE ACL READY\r\n");esp_uart_flush();let deadline=esp_sdk_now()+120000000;let trace_at=0;
    while esp_sdk_now()<deadline {
        if esp_sdk_now()>=trace_at {trace_at=esp_sdk_now()+1000000;esp_uart_write("BLE trace ");esp_uart_hex(esp_bt_receive_sequence);esp_uart_write(" ");esp_uart_hex(bh_rx_packets);esp_uart_write(" ");esp_uart_hex(bh_tx_packets);esp_uart_write(" ");esp_uart_hex(esp_bt_count5);esp_uart_write(" ");esp_uart_hex(esp_bt_count7);esp_uart_write("\r\n");}
        r=esp_ble_poll();if r {bp_word("BLE poll error ",r);bp_word("BLE core error ",bh_error);bp_word("BLE fault ",bh_last_error);return 5;}
        while esp_ble_event()==1 {let kind=bh_event_kind;let token=bh_event_connection;let status=bh_event_status;let detail=bh_event_detail;if esp_ble_consume_event() {return 6;}
            if kind==1 && !status {bp_connection=token;bp_mtu=23;bp_notify=0;bp_connections=bp_connections+1;bp_word("BLE connected token ",token);}
            else if kind==2 && !status {bp_connection=0;bp_notify=0;bp_disconnects=bp_disconnects+1;bp_word("BLE disconnected detail ",detail);if esp_ble_advertise_enable(1) {return 7;}esp_uart_write("BLE ACL READY\r\n");}
            else if kind==8 || kind==9 {bp_word("BLE protocol fault ",status);return 8;}
        }
        r=bp_request();if r {bp_word("BLE request error ",r);return 9;}if bp_notify && bp_connection {store8(bp_reply,0x1b);bh_put16(bp_reply+1,1);let length=bp_size;if length>bp_mtu-3 {length=bp_mtu-3;}nb_copy(bp_reply+3,bp_value,length);r=esp_ble_send(bp_connection,4,bp_reply,length+3);if !r {bp_notify=0;bp_notifications=bp_notifications+1;}else if r!= -11 {return 10;}}
        if bp_connections>=2 && bp_disconnects>=2 && bp_reads>=4 && bp_writes>=2 && bp_notifications>=1 {bp_word("BLE reads ",bp_reads);bp_word("BLE writes ",bp_writes);bp_word("BLE notifications ",bp_notifications);bp_word("BLE ACL RX ",bh_rx_packets);bp_word("BLE ACL TX ",bh_tx_packets);bp_word("BLE event drops ",esp_bt_event_dropped);bp_word("BLE ACL drops ",esp_bt_acl_dropped);esp_uart_write("PASS: physical BLE connections, bidirectional fragmented ACL and notification\r\n");esp_uart_flush();return 0;}esp_sdk_delay(1);
    }esp_uart_write("FAIL: BLE ACL peer timeout\r\n");esp_uart_flush();return 11;
}
