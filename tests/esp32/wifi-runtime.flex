import "../../lib/platform/esp32-xip.flex";
import "../../lib/platform/esp32-ip.flex";
fn main() {
    if esp_sdk_heap_init(0x3ffc8000,98304) || esp_sdk_task_init() {return 1;}esp_irq_enable();let stats=esp32_external("wifi_oracle");
    let config=alloc(192);store64(config+184,0x123456789abcdef0);
    if esp_wifi_station_config(config,"test",4,"testpass",8,3) || load64(config+184)!=0x123456789abcdef0 || esp32_load32(config+120)!=3 {return 2;}
    if esp_wifi_station_config(config,"t",0,"testpass",8,3)!= -22 || esp_wifi_station_config(config,"t",1,"short",5,3)!= -22 || esp_wifi_station_config(config,"t",1,0,0,5)!= -95 {return 3;}
    let hex=alloc(64);let i=0;while i<64 {store8(hex+i,97);i=i+1;}if esp_wifi_station_config(config,"t",1,hex,64,3) {return 4;}store8(hex+63,122);if esp_wifi_station_config(config,"t",1,hex,64,3)!= -22 {return 5;}
    if esp_wifi_station_config(config,"t",1,0,0,0) || esp_wifi_station_config(config,"t",1,"testpass",8,6) || load8(config+129)!=1 {return 6;}
    let event=alloc(48);let post=esp32_callback32(esp_event_post);esp_radio_event_hook=esp32_callback(esp_wifi_event);esp_wifi_initialized=1;
    esp32_call32(post,0,2,0,0,0,0,0,0);if !esp_wifi_started || esp_radio_event_data || esp_radio_event_size {return 7;}
    let free_before=esp_sdk_heap_free();if esp_wifi_join("test",4,"testpass",8,3) || !esp_wifi_connecting || esp_wifi_attempts!=1 || esp32_load32(stats)!=1 || esp32_load32(stats+4)!=1 || esp_sdk_heap_free()!=free_before {return 8;}
    if esp_wifi_join("test",4,"testpass",8,3)!= -16 {return 9;}
    store8(event+33,0xa1);store8(event+38,0xb2);store8(event+39,6);esp32_call32(post,0,4,event,40,0,0,0,0);
    if !esp_wifi_linked || esp_wifi_connecting || esp_wifi_channel!=6 || esp_wifi_bssid!=0xb200000000a1 || esp_wifi_attempts {return 10;}
    if esp_wifi_retry_policy(10,25,2) || esp_wifi_retry_policy(0,25,2)!= -22 {return 11;}
    store8(event+39,201);esp32_call32(post,0,5,event,40,0,0,0,0);if esp_wifi_linked || esp_wifi_reason!=201 || !esp_wifi_retry_at || !esp_wifi_want_link {return 12;}
    esp_wifi_retry_at=1;if esp_wifi_poll() || esp32_load32(stats+4)!=2 {return 13;}
    esp32_store32(stats+32,17);esp_wifi_connecting=0;esp_wifi_retry_at=1;if esp_wifi_poll()!=17 || esp_wifi_want_link || esp_wifi_last_error!= -110 || esp32_load32(stats+4)!=3 {return 14;}
    esp_wifi_want_link=1;if esp_wifi_disconnect() || esp_wifi_want_link || esp32_load32(stats+8)!=1 {return 15;}
    if esp_wifi_frames_init() {return 16;}let frame=alloc(1536);let out=alloc(1544);store64(out+1536,0x12345678);store8(frame,7);let receive=esp32_callback32(esp_wifi_rx_callback);let baseline=esp_sdk_heap_free();
    i=0;while i<8 {store8(frame+13,i);if esp32_call32(receive,frame,14,0x1234,0,0,0,0,0) {return 17;}i=i+1;}
    if esp_wifi_rx_count!=4 || esp_wifi_rx_dropped!=4 || esp32_load32(stats+12)!=8 || esp32_load32(stats+16) || esp32_load32(stats+20) || esp_sdk_heap_free()!=baseline {return 18;}
    if esp_wifi_receive(out,13)!= -90 || esp_wifi_rx_count!=4 {return 19;}
    i=0;while i<4 {if esp_wifi_receive(out,1536)!=14 || load8(out+13)!=i {return 20;}i=i+1;}if esp_wifi_receive(out,1536) {return 21;}
    i=0;while i<16 {store8(frame+13,i);esp32_call32(receive,frame,1536,0x1234,0,0,0,0,0);if esp_wifi_receive(out,1536)!=1536 || load8(out+13)!=i || load64(out+1536)!=0x12345678 {return 22;}i=i+1;}
    esp32_call32(receive,0,14,0x1234,0,0,0,0,0);esp32_call32(receive,frame,1537,0x1234,0,0,0,0,0);if esp_wifi_rx_dropped!=6 || esp32_load32(stats+12)!=26 {return 23;}
    esp_wifi_linked=0;if esp_wifi_transmit(frame,14)!= -107 || esp32_load32(stats+24) {return 24;}esp_wifi_linked=1;if esp_wifi_transmit(frame,14) || esp_wifi_tx_packets!=1 || esp32_load32(stats+24)!=1 {return 25;}
    esp32_store32(stats+36,42);if esp_wifi_transmit(frame,14)!=42 || esp_wifi_tx_packets!=1 || esp_wifi_transmit(frame,1537)!= -22 {return 26;}
    esp_ip_frame=frame;let metadata=alloc(24);if esp_ip_events || esp_ip_udp_bind(4242) || !esp_ip_events {return 27;}
    en_udp_source=0x0a000001;en_udp_source_port=5555;en_udp_target_port=4242;en_udp_data=frame;en_udp_size=14;i=0;
    while i<8 {store8(frame+13,i);esp_ip_udp_deliver();i=i+1;}if esp_ip_event_count!=4 || esp_ip_event_dropped!=4 || esp_ip_udp_receive(out,13,metadata)!= -90 {return 28;}
    i=0;while i<4 {if esp_ip_udp_receive(out,1536,metadata)!=14 || load8(out+13)!=i || load64(metadata)!=0x0a000001 || load64(metadata+8)!=5555 || load64(metadata+16)!=4242 {return 29;}i=i+1;}
    if esp_ip_udp_receive(out,1536,metadata)!= -11 {return 30;}en_udp_size=0;esp_ip_udp_deliver();if esp_ip_udp_receive(out,0,metadata)!=0 || esp_ip_event_count {return 31;}
    if esp_ip_udp_bind(68)!= -22 || esp_ip_udp_bind(65536)!= -22 {return 32;}
    esp_ip_current_address=0x0a000002;en_ip=0;dn_state=1;esp_ip_event_count=2;esp_ip_address_update();if dn_state!=3 || dn_last_error!= -107 || esp_ip_event_count {return 33;}
    // Link transition cancellation must survive the following address-loss
    // pass; completed cached answers cannot remain usable on a new link.
    if tc_init(alloc(4096),4096) || esp_ip_dns_tcp_init() {return 38;}dt_enter();tc_state=4;tc_remote_ip=0x08080808;tc_local_port=50535;tc_remote_port=53;dt_leave();tc_state=4;tc_local_ip=0x0a000002;
    dn_state=1;dn_result=0x0a000003;dn_expires=12345;esp_ip_event_count=2;esp_ip_link_generation=esp_wifi_generation;
    if esp_ip_link_update() || dn_state!=1 {return 34;}esp_wifi_generation=esp_wifi_generation+1;
    if !esp_ip_link_update() || tc_state!=11 || tc_error!= -107 || dn_state!=3 || dn_last_error!= -107 || dn_result || dn_expires || esp_ip_event_count || en_ip || en_mask || en_gateway || en_dns {return 35;}
    dt_enter();let dns_cancelled=tc_state==11 && tc_error== -107;dt_leave();if !dns_cancelled || dn_transport {return 39;}
    esp_ip_current_address=0x0a000002;esp_ip_address_update();if dn_state!=3 || dn_last_error!= -107 || esp_ip_link_update() {return 36;}
    dn_state=2;dn_result=0x0a000003;dn_expires=12345;esp_wifi_generation=esp_wifi_generation+1;esp_ip_link_update();if dn_state || dn_result || dn_expires {return 37;}
    esp_uart_write("PASS: Wi-Fi station ABI, events, bounded reconnect, packet FIFO, vendor ownership and TX guard\r\n");return 0;
}
