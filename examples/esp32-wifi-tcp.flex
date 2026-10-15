import "../lib/platform/esp32-xip.flex";
import "../lib/platform/esp32-ip.flex";
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
    if r || esp_ip_init() {return 7;}deadline=esp_sdk_now()+90000000;
    while !en_ip && esp_sdk_now()<deadline && esp_wifi_want_link {esp_ip_poll();esp_sdk_delay(1);}
    if !en_ip {connect_word("Wi-Fi failure reason ",esp_wifi_reason);connect_word("IP TX error ",esp_ip_last_tx_error);return 8;}
    connect_word("IPv4 address ",en_ip);connect_word("IPv4 gateway ",en_gateway);connect_word("IPv4 DNS ",en_dns);esp_uart_write("PASS: physical DHCP address acquisition\r\n");
    if esp_ip_resolve("example.com",11) {return 9;}deadline=esp_sdk_now()+15000000;while dn_state==1 && esp_sdk_now()<deadline {esp_ip_poll();esp_sdk_delay(1);}
    connect_word("DNS state ",dn_state);connect_word("DNS error ",dn_last_error);if dn_state!=2 {return 10;}connect_word("DNS IPv4 answer ",dn_result);
    let generation=ed_bound_generation;if esp_ip_dhcp_renew() {return 11;}deadline=esp_sdk_now()+15000000;while ed_bound_generation==generation && esp_sdk_now()<deadline {esp_ip_poll();esp_sdk_delay(1);}if ed_bound_generation==generation {return 12;}
    esp_uart_write("PASS: physical DHCP renewal and DNS resolution\r\n");esp_uart_flush();
    if esp_ip_tcp_listen(4243) {return 13;}let echo=esp_sdk_calloc(1,2048);if !echo {return 14;}let pending=0;let offset=0;let received=0;let sent=0;
    esp_uart_write("TCP ECHO READY\r\n");esp_uart_flush();deadline=esp_sdk_now()+45000000;
    while esp_sdk_now()<deadline && tc_state!=11 && tc_state {
        esp_ip_poll();if !pending {let size=esp_ip_tcp_receive(echo,2048);if size>0 {pending=size;offset=0;received=received+size;}else if !size && tc_eof && tc_state==7 && !tc_close_wanted {esp_ip_tcp_close();}else if size!= -11 && size<0 {connect_word("TCP receive error ",size);return 17;}}
        if pending {r=esp_ip_tcp_send(echo+offset,pending);if r>0 {pending=pending-r;offset=offset+r;sent=sent+r;}else if r!= -11 {connect_word("TCP send error ",r);return 18;}}esp_sdk_delay(1);
    }
    connect_word("TCP state ",tc_state);connect_word("TCP error ",tc_error);connect_word("TCP received bytes ",received);connect_word("TCP sent bytes ",sent);connect_word("TCP retransmissions ",tc_retransmits);connect_word("Wi-Fi dropped frames ",esp_wifi_rx_dropped);
    if tc_state || tc_error || !received || sent!=received || pending {return 19;}
    r=esp_wifi_disconnect();if r {return 15;}deadline=esp_sdk_now()+5000000;while esp_wifi_linked && esp_sdk_now()<deadline {esp_sdk_delay(1);}if esp_wifi_linked {return 16;}esp_uart_write("PASS: physical Wi-Fi TCP echo and close\r\n");esp_uart_flush();return 0;
}
