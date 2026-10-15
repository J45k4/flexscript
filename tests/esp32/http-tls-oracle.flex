import "../../lib/platform/esp32-xip.flex";
import "../../lib/platform/esp32-http.flex";
global ht_writes=0;
global ht_received=0;
global ht_close_byte=0;
fn ht_word(label,n) {esp_uart_write(label);esp_uart_hex(n);esp_uart_write("\n");return n;}
fn ht_send(context,buffer,size,d,e,f,g,h) {ht_writes=ht_writes+1;if !(ht_writes&1) {return -0x6880;}if size>17 {size=17;}ht_word("TLS TX ",size);let i=0;while i<size {esp_uart_putc(load8(buffer+i));i=i+1;}esp_uart_flush();return size;}
fn ht_receive(context,buffer,size,d,e,f,g,h) {let n=0;while n<size {let c=esp_uart_read();if c<0 {if n {return n;}return -0x6900;}store8(buffer+n,c);n=n+1;}return n;}
fn ht_connect(local_port) {
    esp_ip_frame=1;let r=esp_http_connect(0x0a000001,443,local_port,"esp32.test",10,1,30000);esp_ip_frame=0;if r {return r;}
    esp32_call32(esp32_external("mbedtls_ssl_set_bio"),et_ssl,0,esp32_callback32(ht_send),esp32_callback32(ht_receive),0,0,0,0);tc_state=4;tc_tx_pending=0;let end=esp_sdk_now()+10000000;
    while esp_http_state==1 && esp_sdk_now()<end {esp_http_poll();esp_sdk_delay(1);}if esp_http_state!=2 {return -1;}return 0;
}
fn ht_close() {
    let r=esp_http_close();if r {return r;}let end=esp_sdk_now()+5000000;
    while esp_http_state!=7 && esp_sdk_now()<end {if et_close_sent {if !et_peer_closed {let read=et_i32(esp32_call32(esp32_external("mbedtls_ssl_read"),et_ssl,ht_close_byte,1,0,0,0,0,0));if read== -0x7880 {et_peer_closed=1;}}if et_peer_closed {tc_state=0;}}esp_http_poll();esp_sdk_delay(1);}if esp_http_state!=7 || es_owner || et_ca_count!=1 {return -1;}return 0;
}
fn ht_response(out,kind) {
    ht_received=0;let end=esp_sdk_now()+10000000;
    while (esp_http_state!=5 || hp_body_used) && esp_http_state!=8 && esp_sdk_now()<end {
        esp_http_poll();let n=esp_http_read(out,128);if n>0 {let i=0;while i<n {let want=(ht_received+i)%251;if kind==1 {want=load8("yes"+ht_received+i);}if load8(out+i)!=want {return -2;}i=i+1;}ht_received=ht_received+n;}else if n!= -11 && n {return n;}esp_sdk_delay(1);
    }if esp_http_state!=5 {return -1;}return 0;
}
fn main() {
    esp32_callback32(esp_dport_access_reg_read);esp32_callback32(phy_enter_critical);esp32_callback32(phy_exit_critical);esp32_callback32(__esp_radio_printf);
    if esp_sdk_heap_init(0x3ffc8000,98304) || esp_sdk_task_init() {return 1;}esp_irq_enable();if tc_init(alloc(4096),4096) {return 2;}let baseline=esp_sdk_heap_free();if esp_tls_set_time(1791990011) || esp_tls_add_ca(ht_ca(),ht_ca_size()) {return 3;}
    esp_wifi_initialized=1;esp_wifi_linked=1;en_ip=0x0a000002;if es_connect(0,0x0a000001,443,50001,"esp32.test",10,1,30000)!= -22 || es_owner {return 23;}tc_state=4;if es_connect(2,0x0a000001,443,50001,"esp32.test",10,1,30000)!= -16 || es_owner || tc_state!=4 {return 24;}tc_state=0;let mode=ht_mode();ht_close_byte=alloc(8);let out=alloc(128);let body=alloc(1000);if ht_connect(50001) {return 4;}
    if esp_tls_reset_session()!= -16 || es_release(1)!= -16 || es_connect(2,0x0a000001,443,50002,"esp32.test",10,1,30000)!= -16 || es_owner!=1 || esp_http_begin("GET",3,"/first",6,ht_body_length(),1) || esp_http_header("X-Test",6,"native",6) || esp_http_end_headers() {return 5;}
    if mode==3 {eh_timeout=50;eh_deadline=esp_sdk_now()/1000+50;}
    if mode==4 {if esp_http_abort() || esp_http_state!=7 || esp_http_error!= -125 || esp_http_read(out,128)!= -125 {return 25;}}else if mode==1 || mode==3 {
        let end=esp_sdk_now()+5000000;while esp_http_state!=8 && esp_sdk_now()<end {esp_http_poll();esp_sdk_delay(1);}let expected= -74;if mode==3 {expected= -110;}if esp_http_state!=8 || esp_http_error!=expected {ht_word("HTTP ERROR ",esp_http_error);return 6;}if esp_http_close() || esp_http_state!=7 {return 7;}
    }else if mode==2 {
        // An early final reply must stop the upload and prohibit connection reuse.
        let end=esp_sdk_now()+5000000;while esp_http_state!=5 && esp_http_state!=8 && esp_sdk_now()<end {esp_http_poll();esp_sdk_delay(1);}if esp_http_state!=5 || esp_http_status!=413 || esp_http_reusable || !eh_early || esp_http_write(body,1)!= -32 || esp_http_close() {return 8;}
    }else {
        if ht_response(out,0) || esp_http_status!=200 || ht_received!=4200 || !esp_http_reusable {ht_word("HTTP FIRST STATE ",esp_http_state);return 9;}let trailer=esp_http_field("x-sum",5,0,1);if trailer<=0 || hp_field_size!=2 || !nb_equal(trailer,"ok",2) {return 10;}
        if esp_http_begin("POST",4,"/fixed",6,137,1) || esp_http_end_headers() {return 11;}let sent=0;let end=esp_sdk_now()+10000000;
        while sent<137 && esp_http_state==4 && esp_sdk_now()<end {esp_http_poll();let i=0;while i<137-sent {store8(body+i,(sent+i)%251);i=i+1;}let n=esp_http_write(body,137-sent);if n>0 {sent=sent+n;}else if n!= -11 {return 12;}esp_sdk_delay(1);}if sent!=137 || esp_http_end_body() || ht_response(out,1) || ht_received!=3 || esp_http_status!=201 || !esp_http_reusable {return 13;}
        if ht_close() || ht_connect(50002) {return 14;}if et_ca_count!=1 || !et_seeded || esp_http_begin("POST",4,"/chunked",8,-1,0) || esp_http_end_headers() {return 15;}sent=0;end=esp_sdk_now()+15000000;
        while sent<3137 && esp_http_state==4 && esp_sdk_now()<end {esp_http_poll();let amount=3137-sent;if amount>1000 {amount=1000;}let i=0;while i<amount {store8(body+i,(sent+i)%251);i=i+1;}let n=esp_http_write(body,amount);if n>0 {sent=sent+n;}else if n!= -11 {return 16;}esp_sdk_delay(1);}if sent!=3137 {return 17;}
        let ended=0;while !ended && esp_http_state==4 && esp_sdk_now()<end {let r=esp_http_end_body();if !r {ended=1;}else if r!= -11 {return 18;}esp_http_poll();esp_sdk_delay(1);}if !ended {return 19;}
        end=esp_sdk_now()+10000000;while esp_http_state!=5 && esp_http_state!=8 && esp_sdk_now()<end {esp_http_poll();esp_sdk_delay(1);}if esp_http_state!=5 || esp_http_status!=204 || esp_http_received || esp_http_reusable {return 20;}if ht_close() {return 21;}
    }
    if esp_tls_deinit() || esp_tls_allocated || esp_sdk_heap_free()!=baseline {ht_word("HTTP HEAP BASE ",baseline);ht_word("HTTP HEAP END ",esp_sdk_heap_free());return 22;}
    esp_uart_write("PASS: HTTP facade and TLS memory reclaimed\n");return 0;
}
