import "../../lib/platform/esp32-xip.flex";
import "../../lib/platform/esp32-gatt.flex";
import "radio-lifecycle-probe.flex";
fn main() {
    esp_uart_write("LIFECYCLE PROBE BT\r\n");let r=lp_init();if r {return r;}let round=0;
    while round<4 {if round==2 {if lp_shared() {return 4;}}lp_word("CYCLE ",round);r=esp_bt_controller_init();lp_word("INIT ",r);if r {return 5;}esp_irq_enable();
        if esp_bt_controller_init()!= -16 {return 6;}
        if round<2 {r=esp_bt_hci_command(0x0c03,0,0);lp_word("HCI RESET ",r);if r {return 7;}r=esp_bt_hci_command(0x1009,0,0);lp_word("HCI ADDRESS ",r);if r {return 8;}}
        // A host reserves the fresh HCI stream before issuing any raw commands.
        if round>=2 {r=esp_ble_init(1);lp_word("BLE HOST INIT ",r);if r || esp_bt_controller_deinit()!= -16 {return 12;}r=esp_gatt_init(4,32,23);lp_word("GATT INIT ",r);if r || esp_ble_stop()!= -16 {return 13;}r=esp_gatt_stop();}else {r=esp_bt_controller_deinit();}lp_word("DEINIT ",r);if r {return 9;}
        if esp_bt_controller_deinit() || esp_bt_rx || esp_bt_osi || esp_bt_initialized || esp_bt_callbacks || esp_irq_soft_handler || (esp32_irq_enabled()&128) {return 10;}
        r=lp_check();lp_word("OWNERSHIP CHECK ",r);if r {return 11;}round=round+1;
    }
    esp_uart_write("CONTROLLER DEINIT RETURNED\r\nDEINITIALIZED\r\nLIFECYCLE VENDOR RESULT 0000000000000000\r\n");esp_uart_flush();return 0;
}
