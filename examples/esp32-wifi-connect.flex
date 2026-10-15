import "../lib/platform/esp32-xip.flex";
import "../lib/platform/esp32-wifi.flex";
import "../lib/platform/esp32-radio-clock.flex";
fn connect_word(label,value) {esp_uart_write(label);esp_uart_hex(value);esp_uart_write("\r\n");return value;}
// Provision over the existing UART bridge; never echo network credentials.
fn connect_line(buffer,capacity) {
    let size=0;let end=esp_sdk_now()+60000000;
    while esp_sdk_now()<end {let c=esp_uart_read();if c<0 {esp_sdk_delay(1);}else if c==10 {return size;}else if c!=13 {if size>=capacity {return -90;}store8(buffer+size,c);size=size+1;}}return -110;
}
fn main() {
    esp_radio_clock_init();esp_radio_cpu160();if esp_sdk_heap_init(0x3ffc8000,98304) || esp_sdk_task_init() {return 1;}esp_irq_enable();
    let ssid=esp_sdk_calloc(1,32);let password=esp_sdk_calloc(1,64);let frame=esp_sdk_calloc(1,1536);if !ssid || !password || !frame {return 2;}
    esp_uart_write("WIFI PROVISION SSID\r\n");let ssid_size=connect_line(ssid,32);if ssid_size<=0 {return 3;}
    esp_uart_write("WIFI PROVISION PASSWORD\r\n");let password_size=connect_line(password,64);if password_size<0 {return 4;}
    let r=esp_wifi_station_init();connect_word("Wi-Fi station init ",r);if r {return 5;}
    let deadline=esp_sdk_now()+5000000;while !esp_wifi_started && esp_sdk_now()<deadline {esp_sdk_delay(1);}if !esp_wifi_started {return 6;}
    let auth=3;if !password_size {auth=0;}r=esp_wifi_join(ssid,ssid_size,password,password_size,auth);let i=0;while i<64 {store8(password+i,0);i=i+1;}esp_sdk_free(password);esp_sdk_free(ssid);
    connect_word("Wi-Fi join request ",r);if r {return 7;}deadline=esp_sdk_now()+90000000;
    while !esp_wifi_linked && esp_sdk_now()<deadline && esp_wifi_want_link {esp_wifi_poll();esp_sdk_delay(1);}
    if !esp_wifi_linked {connect_word("Wi-Fi failure reason ",esp_wifi_reason);connect_word("Wi-Fi last error ",esp_wifi_last_error);return 8;}
    connect_word("Wi-Fi channel ",esp_wifi_channel);connect_word("Wi-Fi available SDK bytes ",esp_sdk_heap_free());
    esp_uart_write("PASS: physical Wi-Fi station association\r\n");esp_uart_flush();
    deadline=esp_sdk_now()+10000000;let received=0;while esp_sdk_now()<deadline {if esp_wifi_receive(frame,1536)>0 {received=received+1;}esp_wifi_poll();esp_sdk_delay(1);}
    connect_word("Wi-Fi Ethernet frames ",received);connect_word("Wi-Fi dropped frames ",esp_wifi_rx_dropped);
    r=esp_wifi_disconnect();if r {return 9;}deadline=esp_sdk_now()+5000000;while esp_wifi_linked && esp_sdk_now()<deadline {esp_sdk_delay(1);}if esp_wifi_linked {return 10;}
    if esp_wifi_reconnect() {return 11;}deadline=esp_sdk_now()+30000000;while !esp_wifi_linked && esp_sdk_now()<deadline {esp_wifi_poll();esp_sdk_delay(1);}if !esp_wifi_linked {return 12;}
    esp_uart_write("PASS: physical Wi-Fi association and reconnect\r\n");esp_uart_flush();esp_wifi_disconnect();esp_sdk_free(frame);return 0;
}
