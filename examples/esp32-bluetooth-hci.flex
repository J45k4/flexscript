import "../lib/platform/esp32-xip.flex";
import "../lib/platform/esp32-bluetooth.flex";
import "../lib/platform/esp32-radio-clock.flex";
fn bt_word(label,value) {esp_uart_write(label);esp_uart_hex(value);esp_uart_write("\r\n");return value;}
fn main() {
    esp_uart_write("Flexscript Bluetooth HCI probe\r\n");esp_radio_clock_init();esp_radio_cpu160();if esp_sdk_heap_init(0x3ffc8000,98304) || esp_sdk_task_init() {return 1;}esp_irq_enable();
    let r=esp_bt_controller_init();bt_word("BT init ",r);if r {return 2;}
    r=esp_bt_hci_command(0x0c03,0,0);bt_word("HCI reset ",r);if r {return 3;}
    r=esp_bt_hci_command(0x1001,0,0);bt_word("HCI version status ",r);if r {return 4;}
    bt_word("HCI version ",load8(esp_bt_rx+7));
    r=esp_bt_hci_command(0x1009,0,0);bt_word("HCI address status ",r);if r {return 9;}
    let addr=0;let j=0;while j<6 {addr=addr|(load8(esp_bt_rx+7+j)<<(j*8));j=j+1;}bt_word("HCI address ",addr);
    let adv=esp_sdk_calloc(1,32);if !adv {return 5;}
    store8(adv,160);store8(adv+2,160);store8(adv+4,3);store8(adv+13,7);
    r=esp_bt_hci_command(0x2006,adv,15);bt_word("HCI advertising parameters ",r);if r {return 6;}
    let i=0;while i<32 {store8(adv+i,0);i=i+1;}
    store8(adv,15);store8(adv+1,2);store8(adv+2,1);store8(adv+3,6);store8(adv+4,11);store8(adv+5,9);let name="Flexscript";i=0;while i<10 {store8(adv+6+i,load8(name+i));i=i+1;}
    r=esp_bt_hci_command(0x2008,adv,32);bt_word("HCI advertising data ",r);if r {return 7;}
    store8(adv,1);r=esp_bt_hci_command(0x200a,adv,1);bt_word("HCI advertising enable ",r);if r {return 8;}
    esp_uart_write("PASS: physical Bluetooth controller HCI reset and version\r\n");esp_uart_flush();esp_sdk_free(adv);while 1 {esp_sdk_delay(1);}return 0;
}
