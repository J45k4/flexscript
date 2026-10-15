import "../lib/platform/esp32-xip.flex";
import "../lib/platform/esp32-radio-clock.flex";
import "../lib/platform/esp32-gatt.flex";
// Public read/write/notify/indicate demo. Pairing/bonds remain T139.
// Service c70a0001-19ad-4fe0-a8df-ea860185b3d1, value c70a0002-... .
global demo_token=0;
global demo_value=0;
global demo_changed=0;
global demo_smp=0;
fn demo_word(label,value) {esp_uart_write(label);esp_uart_hex(value);esp_uart_write("\r\n");return value;}
fn demo_uuid(out,text) {let i=0;while i<16 {store8(out+i,(nb_hex(load8(text+i*2))<<4)|nb_hex(load8(text+i*2+1)));i=i+1;}return out;}
fn demo_events() {
    while esp_ble_event()==1 {let kind=bh_event_kind;let token=bh_event_connection;let status=bh_event_status;if esp_ble_consume_event() {return -71;}
        if kind==1 && !status {demo_token=token;demo_changed=0;demo_word("GATT connected token ",token);}
        else if kind==2 && !status {demo_token=0;demo_changed=0;esp_uart_write("GATT disconnected\r\n");let r=esp_ble_advertise_enable(1);if r {return r;}}
        else if kind==8 {return status;}
    }
    if demo_token {while esp_gatt_event(demo_token)==1 {let kind=ga_event_kind;let handle=ga_event_handle;let error=ga_event_status;if kind==1 && handle==demo_value {demo_changed=1;demo_word("GATT write fragment bytes ",ga_event_size);}else if kind==2 {demo_changed=1;}else if kind==3 {esp_uart_write("GATT indication confirmed\r\n");}else if kind==4 {demo_word("GATT bearer error ",error);}if esp_gatt_consume_event(demo_token) {return -71;}}}return 0;
}
fn demo_security() {
    // The example declines pairing instead of leaving an SMP PDU blocking ATT.
    // A real security manager will own CID6 under T139.
    if demo_token && esp_ble_message(demo_token)==1 && bh_message_cid==6 {if bh_message_size && load8(bh_message_data)!=5 {let r=esp_ble_send(demo_token,6,demo_smp,2);if r== -11 {return 0;}if r {return r;}}return esp_ble_consume(demo_token);}return 0;
}
fn demo_notify() {
    if !demo_token || !demo_changed {return 0;}let bits=esp_gatt_subscriptions(demo_token,demo_value);if bits<0 {return bits;}if !bits {demo_changed=0;return 0;}let indicate=0;if !(bits&1) {indicate=1;}let r=esp_gatt_value(demo_value);if r!=1 {return r;}let n=ga_value_size;let c=ga_conn(demo_token);let max=load64(c+8)-3;if n>max {n=max;}r=esp_gatt_notify(demo_token,demo_value,ga_value_data,n,indicate);if r== -11 {return 0;}if !r {demo_changed=0;}return r;
}
fn main() {
    esp_uart_write("Flexscript native BLE GATT server\r\n");esp_radio_clock_init();esp_radio_cpu160();if esp_sdk_heap_init(0x3ffc8000,98304) || esp_sdk_task_init() {return 1;}esp_irq_enable();let r=esp_ble_start(1);if demo_word("BLE init ",r) {return 2;}if demo_word("GATT init ",esp_gatt_init(24,2048,247)) {return 3;}
    let uuid=alloc(16);let adv=alloc(32);demo_smp=alloc(8);if uuid<=0 || adv<=0 || demo_smp<=0 {return 4;}store8(demo_smp,5);store8(demo_smp+1,5);
    if ga_standard_services("FlexscriptGATT",14,0) {return 5;}demo_uuid(uuid,"d1b3850186eadfa8e04fad1901000ac7");if ga_service(uuid,16,1)<1 {return 6;}
    nb_zero(adv,32);store8(adv,2);store8(adv+1,1);store8(adv+2,6);store8(adv+3,17);store8(adv+4,7);nb_copy(adv+5,uuid,16);store8(adv+21,9);store8(adv+22,9);nb_copy(adv+23,"FlexGATT",8);
    store8(uuid+12,2);demo_value=ga_characteristic(uuid,16,190,3,"hello",5,240);if demo_value<1 || ga_descriptor(ga_uuid16(0x2901),2,1,"Flexscript value",16,16)<1 || esp_gatt_start() {return 7;}demo_word("GATT value handle ",demo_value);
    let address=0;let i=0;while i<6 {address=address|(load8(esp_ble_address+i)<<(i*8));i=i+1;}demo_word("BLE address ",address);demo_word("GATT SDK free ",esp_sdk_heap_free());if demo_word("BLE advertising ",esp_ble_advertise(adv,31,0,0,160)) {return 8;}esp_uart_write("BLE GATT READY\r\n");esp_uart_flush();
    while 1 {r=esp_gatt_poll();if r {demo_word("GATT poll error ",r);return 9;}r=demo_events();if r {return 10;}r=demo_security();if r {return 11;}r=demo_notify();if r {demo_word("GATT notification error ",r);return 12;}esp_sdk_delay(1);}return 0;
}
