import "../lib/platform/esp32-xip.flex";
import "../lib/platform/esp32-bluetooth.flex";
import "../lib/platform/esp32-radio-clock.flex";
fn scan_word(label,value) {esp_uart_write(label);esp_uart_hex(value);esp_uart_write("\r\n");return value;}
fn main() {
    esp_uart_write("Flexscript passive Bluetooth scan\r\n");esp_radio_clock_init();esp_radio_cpu160();
    if esp_sdk_heap_init(0x3ffc8000,98304) || esp_sdk_task_init() {return 1;}esp_irq_enable();
    let r=esp_bt_controller_init();if scan_word("BT init ",r) {return 2;}
    if scan_word("HCI reset ",esp_bt_hci_command(0x0c03,0,0)) {return 3;}
    let params=esp_sdk_calloc(1,8);if !params {return 4;}
    // Command Complete/Status and LE Meta events; LE Advertising Report only.
    store8(params+1,0x60);store8(params+7,0x20);if esp_bt_hci_command(0x0c01,params,8) {return 5;}
    store8(params+1,0);store8(params+7,0);store8(params,2);if esp_bt_hci_command(0x2001,params,8) {return 6;}
    let i=0;while i<8 {store8(params+i,0);i=i+1;}
    // Passive scan, 100 ms interval/window, public address, no whitelist.
    store8(params+1,160);store8(params+3,160);if esp_bt_hci_command(0x200b,params,7) {return 7;}
    store8(params,1);store8(params+1,0);if esp_bt_hci_command(0x200c,params,2) {return 8;}
    let reports=0;let until=esp_sdk_now()+5000000;
    while esp_sdk_now()<until {
        while esp_bt_hci_next_event() {if esp_bt_rx_size>=5 && load8(esp_bt_rx)==4 && load8(esp_bt_rx+1)==0x3e && load8(esp_bt_rx+3)==2 {reports=reports+load8(esp_bt_rx+4);}}
        esp_sdk_delay(1);
    }
    store8(params,0);store8(params+1,0);if esp_bt_hci_command(0x200c,params,2) {return 9;}
    scan_word("BLE advertising reports ",reports);scan_word("Dropped host events ",esp_bt_event_dropped);esp_sdk_free(params);
    if !reports {return 10;}esp_uart_write("PASS: physical Bluetooth passive scan received advertising reports\r\n");esp_uart_flush();return 0;
}
