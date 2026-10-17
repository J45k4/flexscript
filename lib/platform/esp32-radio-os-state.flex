// Shared vendor OS state; chip wrappers select MMIO, IRQ and PHY contracts.
global esp_radio_osi=0;
global esp_radio_nvs_table=0;
global esp_radio_events=0;
global esp_radio_scan_done=0;
global esp_radio_scan_status= -1;
global esp_radio_last_event=0;
global esp_radio_phy_cal=0;
global esp_radio_phy_init_data=0;
global esp_radio_phy_result=0;
global esp_radio_phy_calibrated=0;
global esp_radio_callback_fault=0;
global esp_radio_log=0;
global esp_radio_event_hook=0;
global esp_radio_event_data=0;
global esp_radio_event_size=0;
fn esp_radio_fail(code) {esp_radio_callback_fault=code;esp_uart_write("RADIO callback unsupported ");esp_uart_hex(code);esp_uart_write("\r\n");while 1 {}return 0;}
