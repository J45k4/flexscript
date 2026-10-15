import "esp32-wifi.flex";
import "../net/dhcp.flex";
import "../net/dns.flex";
import "../net/tcp.flex";
import "../net/dns-tcp.flex";
// Cooperative Wi-Fi/IP adapter. Poll from one application task; packet views
// never escape the core. Application UDP uses a bounded four-datagram queue.
global esp_ip_frame=0;
global esp_ip_fragments=0;
global esp_ip_events=0;
global esp_ip_event_head=0;
global esp_ip_event_count=0;
global esp_ip_event_dropped=0;
global esp_ip_bound_port=0;
global esp_ip_link_generation= -1;
global esp_ip_notified_generation=0;
global esp_ip_current_address=0;
global esp_ip_tx_errors=0;
global esp_ip_last_tx_error=0;
fn esp_ip_init() {
    if esp_ip_frame {return -16;}if !esp_wifi_initialized {return -19;}
    let work=esp_sdk_calloc(1,4096);let frame=esp_sdk_calloc(1,1536);let fragments=esp_sdk_calloc(1,2048);let mac=esp_sdk_calloc(1,8);
    if !work || !frame || !fragments || !mac {esp_sdk_free(work);esp_sdk_free(frame);esp_sdk_free(fragments);esp_sdk_free(mac);return -12;}
    esp_radio_cb_read_mac(mac,0,0,0,0,0,0,0);let r=en_init(mac,work,4096);esp_sdk_free(mac);if !r {r=en_fragment_init(fragments,2048);}if !r {r=ed_acd(1,esp_radio_cb_random(0,0,0,0,0,0,0,0));}if r {esp_sdk_free(work);esp_sdk_free(frame);esp_sdk_free(fragments);return r;}
    esp_ip_frame=frame;esp_ip_fragments=fragments;return 0;
}
fn esp_ip_flush() {
    if !en_tx_size {return 0;}let r=esp_wifi_transmit(en_tx,en_tx_size);if !r {en_tx_size=0;esp_ip_last_tx_error=0;}else {esp_ip_tx_errors=esp_ip_tx_errors+1;esp_ip_last_tx_error=r;}return r;
}
fn esp_ip_udp_bind(port) {
    if !esp_ip_frame {return -19;}if port<1 || port>65535 || port==68 || port==dn_port {return -22;}
    if !esp_ip_events {esp_ip_events=esp_sdk_calloc(4,1536);if !esp_ip_events {return -12;}}esp_ip_bound_port=port;esp_ip_event_head=0;esp_ip_event_count=0;return 0;
}
fn esp_ip_udp_deliver() {
    if en_udp_target_port!=esp_ip_bound_port || !esp_ip_bound_port {return 0;}if esp_ip_event_count==4 || en_udp_size>1472 {esp_ip_event_dropped=esp_ip_event_dropped+1;return 0;}
    let slot=(esp_ip_event_head+esp_ip_event_count)&3;let p=esp_ip_events+slot*1536;store64(p,en_udp_source);store64(p+8,en_udp_source_port);store64(p+16,en_udp_target_port);store64(p+24,en_udp_size);en_copy(p+32,en_udp_data,en_udp_size);esp_ip_event_count=esp_ip_event_count+1;return 0;
}
fn esp_ip_udp_receive(buffer,capacity,metadata) {
    if !esp_ip_frame {return -19;}if !buffer || !metadata || capacity<0 {return -22;}if !esp_ip_event_count {return -11;}
    let p=esp_ip_events+esp_ip_event_head*1536;let size=load64(p+24);if size>capacity {return -90;}en_copy(buffer,p+32,size);store64(metadata,load64(p));store64(metadata+8,load64(p+8));store64(metadata+16,load64(p+16));esp_ip_event_head=(esp_ip_event_head+1)&3;esp_ip_event_count=esp_ip_event_count-1;return size;
}
fn esp_ip_udp_send(ip,port,buffer,size) {
    if !esp_ip_frame || !en_ip || !esp_wifi_linked {return -107;}if !esp_ip_bound_port {return -99;}en_now=esp_sdk_now()/1000;return en_udp_send(ip,esp_ip_bound_port,port,buffer,size);
}
fn esp_ip_resolve(name,size) {
    let id=esp_radio_cb_random(0,0,0,0,0,0,0,0)&65535;if !id {id=1;}if 49152+(id&16383)==esp_ip_bound_port {id=(id+1)&65535;if !id {id=1;}}return dn_start(name,size,id,esp_sdk_now()/1000);
}
fn esp_ip_resolve_tcp(name,size) {let r=esp_ip_resolve(name,size);if !r {dn_transport=1;}return r;}
fn esp_ip_dhcp_renew() {if ed_state!=3 {return -16;}ed_state=4;ed_retries=0;ed_retry_at=esp_sdk_now()/1000;return 0;}
// TCP memory is allocated only when the first client/listener is opened.
fn esp_ip_tcp_init() {
    if !esp_ip_frame || !en_ip || !esp_wifi_linked {return -107;}if tc_workspace {return 0;}let work=esp_sdk_calloc(1,4096);if !work {return -12;}let r=tc_init(work,4096);if r {esp_sdk_free(work);}return r;
}
fn esp_ip_tcp_connect(ip,port,local_port) {let r=esp_ip_tcp_init();if r {return r;}return tc_connect(ip,port,local_port,esp_radio_cb_random(0,0,0,0,0,0,0,0),esp_sdk_now()/1000);}
fn esp_ip_tcp_listen(port) {let r=esp_ip_tcp_init();if r {return r;}return tc_listen(port,esp_radio_cb_random(0,0,0,0,0,0,0,0),esp_sdk_now()/1000);}
fn esp_ip_tcp_send(buffer,size) {if !esp_ip_frame || !en_ip || !esp_wifi_linked {return -107;}return tc_send(buffer,size,esp_sdk_now()/1000);}
fn esp_ip_tcp_receive(buffer,capacity) {return tc_receive(buffer,capacity);}
fn esp_ip_tcp_close() {return tc_close();}
fn esp_ip_tcp_lost() {if tc_workspace && tc_state && tc_state!=11 {tc_fail(-107);}return 0;}
fn esp_ip_dns_tcp_init() {
    if dt_context {return 0;}let work=esp_sdk_calloc(1,4096);let context=esp_sdk_calloc(1,512);let application=esp_sdk_calloc(1,512);let receive=esp_sdk_calloc(1,4098);
    if !work || !context || !application || !receive {esp_sdk_free(work);esp_sdk_free(context);esp_sdk_free(application);esp_sdk_free(receive);return -12;}
    let r=dt_init(work,4096,context,application,receive,4098);if r {esp_sdk_free(work);esp_sdk_free(context);esp_sdk_free(application);esp_sdk_free(receive);}return r;
}
fn esp_ip_dns_lost() {
    if dn_state==1 {dn_state=3;dn_last_error= -107;}else if dn_state==2 {dn_state=0;dn_last_error=0;}dn_result=0;dn_expires=0;dt_link_lost();return 0;
}
fn esp_ip_address_update() {
    if en_ip!=esp_ip_current_address {if tc_workspace && tc_local_ip!=en_ip {esp_ip_tcp_lost();}en_fragment_reset();esp_ip_current_address=en_ip;esp_ip_event_head=0;esp_ip_event_count=0;esp_ip_dns_lost();}return 0;
}
fn esp_ip_link_update() {
    if esp_ip_link_generation==esp_wifi_generation {return 0;}
    esp_ip_link_generation=esp_wifi_generation;ac_reset();en_fragment_reset();esp_ip_dns_lost();esp_ip_tcp_lost();en_ip=0;en_mask=0;en_gateway=0;en_dns=0;en_tx_size=0;ed_state=0;esp_ip_event_head=0;esp_ip_event_count=0;return 1;
}
fn esp_ip_poll() {
    if !esp_ip_frame {return -19;}esp_wifi_poll();let now=esp_sdk_now()/1000;en_now=now;esp_ip_link_update();
    if !esp_wifi_linked {return -107;}if !ed_state {let xid=esp_radio_cb_random(0,0,0,0,0,0,0,0);if !xid {xid=1;}ed_start(xid,now);}
    en_fragment_expire(now);esp_ip_flush();let i=0;let stopped=0;
    while i<8 && !stopped {
        let size=esp_wifi_receive(esp_ip_frame,1536);if size<=0 {stopped=1;}else {let kind=en_input(esp_ip_frame,size,now);
        if kind==6 {if !dt_input(now) && tc_workspace {tc_input(now);}}if kind==17 {if en_udp_source_port==67 && en_udp_target_port==68 {ed_input(now);}else if dn_state==1 && en_udp_source_port==53 && en_udp_target_port==dn_port {dn_input(now);}else {esp_ip_udp_deliver();}}
        esp_ip_flush();}i=i+1;
    }
    ed_poll(now);if en_ip && ed_bound_generation!=esp_ip_notified_generation {let r=esp32_call32(esp32_external("esp_wifi_internal_set_sta_ip"),0,0,0,0,0,0,0,0);if !r {esp_ip_notified_generation=ed_bound_generation;}}
    esp_ip_address_update();if dn_state==1 {dn_poll(now);if dn_state==1 && dn_transport && !dt_context {let r=esp_ip_dns_tcp_init();if r {dn_state=3;dn_last_error=r;dn_transport=0;}}}
    if dt_context {dt_poll(now,esp_radio_cb_random(0,0,0,0,0,0,0,0));esp_ip_flush();}if tc_workspace {tc_poll(now);}esp_ip_flush();return 0;
}
