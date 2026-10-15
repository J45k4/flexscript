import "../../lib/platform/esp32-xip.flex";
import "../../lib/platform/esp32-tls.flex";
// QEMU-only stream adapter. The independent peer is Python/OpenSSL, transported
// over UART because QEMU has no vendor Wi-Fi radio. Firmware APIs stay native.
global to_writes=0;
global to_serviced=0;
global to_worker=0;
fn to_network_service(a,b,c,d,e,f,g,h) {to_serviced=1;return 0;}
fn to_word(label,n) {esp_uart_write(label);esp_uart_hex(n);esp_uart_write("\n");return n;}
fn to_send(context,buffer,size,d,e,f,g,h) {if to_mode()==10 && !to_serviced {esp_uart_write("FAIL: queued network worker must run before TLS\n");return -0x004e;}if to_mode()==7 {to_writes=to_writes+1;if !(to_writes&1) {return -0x6880;}if size>17 {size=17;}}to_word("TLS TX ",size);let i=0;while i<size {esp_uart_putc(load8(buffer+i));i=i+1;}esp_uart_flush();return size;}
fn to_receive(context,buffer,size,d,e,f,g,h) {let n=0;while n<size {let c=esp_uart_read();if c<0 {if n {return n;}if to_mode()==6 && esp_tls_state==3 {return 0;}return -0x6900;}store8(buffer+n,c);n=n+1;}return n;}
fn main() {
    esp32_callback32(esp_dport_access_reg_read);esp32_callback32(phy_enter_critical);esp32_callback32(phy_exit_critical);esp32_callback32(__esp_radio_printf);
    if esp_sdk_heap_init(0x3ffc8000,98304) || esp_sdk_task_init() {return 1;}esp_irq_enable();if tc_init(alloc(4096),4096) {return 12;}let baseline=esp_sdk_heap_free();
    let got=alloc(4);let random=alloc(8);esp32_store32(got,99);if mbedtls_hardware_poll(0,random,8,got,0,0,0,0)!= -60 || esp32_load32(got) {return 2;}
    esp_tls_set_time(7258118400);let clock=alloc(8);let wide=esp32_call64(esp32_callback32(flex_tls_time),clock,0,0,0,0,0,0,0);if wide<7258118400 || wide>7258118401 || load64(clock)!=wide {return 13;}
    let mode=to_mode();if mode==9 {let remaining=0x3ffc8000-esp32_load32(esp32_state());if alloc(remaining)<0 || esp_tls_init()!= -12 || et_workspace || esp_sdk_heap_free()!=baseline {return 19;}esp_uart_write("PASS: TLS memory reclaimed\n");return 0;}let now=1791990011;if mode==2 {now=1956528000;}if mode==3 {now=1672531200;}if esp_tls_set_time(now) || esp_tls_add_ca(to_ca(),to_ca_size()) {return 3;}
    if esp_tls_add_ca(to_ca(),to_ca_size()) {return 14;}let allocated=esp_sdk_heap_free();if esp_tls_add_ca("invalid",7)==0 || esp_sdk_heap_free()!=allocated || et_ca_count!=2 {return 4;}
    esp_wifi_initialized=1;esp_wifi_linked=1;en_ip=0x0a000002;let host="esp32.test";let size=10;if mode==1 {host="wrong.test";size=10;}
    esp_ip_frame=1;let connected=esp_tls_connect(0x0a000001,443,50001,host,size,30000);esp_ip_frame=0;if connected {to_word("TLS CONFIG ERROR ",connected);return 5;}
    if mode==8 {tc_fail(-111);let failed=esp_tls_poll();if failed!= -111 || esp_tls_state!=6 || esp_tls_error!= -111 {to_word("FAIL: TCP error propagation ",failed);return 17;}if esp_tls_deinit() || esp_tls_allocated || esp_sdk_heap_free()!=baseline {return 18;}esp_uart_write("PASS: TLS memory reclaimed\n");return 0;}
    // Swap only the test transport after normal TLS configuration. No host
    // certificate, trust or cipher decisions are bypassed.
    esp32_call32(esp32_external("mbedtls_ssl_set_bio"),et_ssl,0,esp32_callback32(to_send),esp32_callback32(to_receive),0,0,0,0);tc_state=4;tc_tx_pending=0;
    if mode==10 {to_worker=esp_sdk_task_create(esp32_callback32(to_network_service),0,2048,1);if !to_worker {return 20;}}
    esp_uart_write("TLS ORACLE START\n");let end=esp_sdk_now()+30000000;
    while esp_tls_state!=3 && esp_tls_state!=6 && esp_sdk_now()<end {esp_tls_poll();esp_sdk_delay(1);}
    to_word("TLS STATE ",esp_tls_state);to_word("TLS ERROR ",esp_tls_error);to_word("TLS VERIFY ",esp_tls_verify_flags);
    if mode==6 {if esp_tls_state!=6 || esp_tls_error!= -104 || et_rx_used {return 16;}esp_uart_write("PASS: TLS truncation rejected\n");}
    else if mode>=1 && mode<=4 {if esp_tls_state!=6 || !esp_tls_verify_flags {return 6;}}
    else {
        if esp_tls_state!=3 || esp_tls_verify_flags || esp_tls_send("Flexscript TLS request",22)!=22 {return 7;}let response=alloc(128);let used=0;
        end=esp_sdk_now()+10000000;while used<23 && esp_tls_state!=6 && esp_sdk_now()<end {esp_tls_poll();let n=esp_tls_receive(response+used,128-used);if n>0 {used=used+n;}else if n!= -11 && !((mode==5 || mode==6) && esp_tls_state==6) {return 8;}esp_sdk_delay(1);}
        if mode==5 || mode==6 {if used || esp_tls_state!=6 || !esp_tls_error {return 15;}esp_uart_write("PASS: TLS unauthenticated or truncated data rejected\n");}else {if used!=23 || !dn_equal(response,"OpenSSL verified reply!",23) {return 9;}esp_uart_write("PASS: verified TLS exchange\n");}
        if !mode || mode==7 || mode==10 {esp_tls_close();end=esp_sdk_now()+5000000;while !et_close_sent && esp_tls_state!=6 && esp_sdk_now()<end {esp_tls_poll();esp_sdk_delay(1);}if !et_close_sent {return 10;}esp_tls_state=5;}
    }
    if to_worker {if !to_serviced || esp_sdk_task_reap(to_worker) {return 21;}to_worker=0;}
    if esp_tls_deinit() || esp_sdk_heap_free()!=baseline || esp_tls_allocated {to_word("HEAP BEFORE ",baseline);to_word("HEAP AFTER ",esp_sdk_heap_free());return 11;}esp_uart_write("PASS: TLS memory reclaimed\n");return 0;
}
