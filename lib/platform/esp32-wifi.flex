import "esp32-radio-os.flex";
// Original ESP32 station facade for the pinned esp-wifi-sys ABI. Credentials
// remain in RAM. Call poll regularly; vendor callbacks never reconnect inline.
global esp_wifi_initialized=0;
global esp_wifi_vendor_initialized=0;
global esp_wifi_vendor_running=0;
global esp_wifi_supplicant=0;
global esp_wifi_lifecycle_busy=0;
global esp_wifi_control_task=0;
global esp_wifi_cleanup_error=0;
global esp_wifi_init_config=0;
global esp_wifi_started=0;
global esp_wifi_linked=0;
global esp_wifi_connecting=0;
global esp_wifi_want_link=0;
global esp_wifi_attempts=0;
global esp_wifi_retry_base=250;
global esp_wifi_retry_max=8000;
global esp_wifi_retry_limit=8;
global esp_wifi_retry_at=0;
global esp_wifi_connect_until=0;
global esp_wifi_last_error=0;
global esp_wifi_reason=0;
global esp_wifi_generation=0;
global esp_wifi_channel=0;
global esp_wifi_bssid=0;
global esp_wifi_rx_ring=0;
global esp_wifi_rx_head=0;
global esp_wifi_rx_count=0;
global esp_wifi_rx_busy=0;
global esp_wifi_rx_dropped=0;
global esp_wifi_rx_packets=0;
global esp_wifi_tx_packets=0;
fn esp_wifi_retry_policy(base_ms,max_ms,attempt_limit) {
    if base_ms<1 || max_ms<base_ms || max_ms>60000 || attempt_limit<0 || attempt_limit>65535 {return -22;}
    esp_wifi_retry_base=base_ms;esp_wifi_retry_max=max_ms;esp_wifi_retry_limit=attempt_limit;return 0;
}
fn esp_wifi_schedule_retry(now) {
    esp_wifi_connecting=0;esp_wifi_connect_until=0;
    if !esp_wifi_want_link || !esp_wifi_started {esp_wifi_retry_at=0;return 0;}
    if esp_wifi_retry_limit && esp_wifi_attempts>=esp_wifi_retry_limit {esp_wifi_want_link=0;esp_wifi_retry_at=0;esp_wifi_last_error= -110;return -110;}
    let delay=esp_wifi_retry_base;let i=1;while i<esp_wifi_attempts && delay<esp_wifi_retry_max {delay=delay*2;i=i+1;}
    if delay>esp_wifi_retry_max {delay=esp_wifi_retry_max;}esp_wifi_retry_at=now+delay*1000;return 0;
}
fn esp_wifi_event(id) {
    let data=esp_radio_event_data;let size=esp_radio_event_size;
    if id==2 {esp_wifi_started=1;}
    else if id==3 {esp_wifi_started=0;esp_wifi_linked=0;esp_wifi_connecting=0;esp_wifi_retry_at=0;esp_wifi_generation=esp_wifi_generation+1;}
    else if id==4 {
        esp_wifi_linked=1;esp_wifi_connecting=0;esp_wifi_retry_at=0;esp_wifi_connect_until=0;esp_wifi_attempts=0;esp_wifi_last_error=0;esp_wifi_generation=esp_wifi_generation+1;
        esp_wifi_channel=0;esp_wifi_bssid=0;if data && size>=40 {esp_wifi_channel=load8(data+39);let i=0;while i<6 {esp_wifi_bssid=esp_wifi_bssid|(load8(data+33+i)<<(i*8));i=i+1;}}
    }else if id==5 {
        esp_wifi_linked=0;esp_wifi_reason=255;if data && size>=40 {esp_wifi_reason=load8(data+39);}esp_wifi_generation=esp_wifi_generation+1;esp_wifi_schedule_retry(esp_sdk_now());
    }return 0;
}
// wifi_sta_config_t is 184 bytes in the pinned ABI. SSID/password may be
// non-NUL-terminated at their maximum lengths; explicit lengths are required.
fn esp_wifi_station_config(config,ssid,ssid_size,password,password_size,auth) {
    if !config || !ssid || ssid_size<1 || ssid_size>32 || password_size<0 || password_size>64 || (password_size && !password) {return -22;}
    if auth!=0 && auth!=2 && auth!=3 && auth!=4 && auth!=6 && auth!=7 {return -95;}
    if (!auth && password_size) || (auth && password_size<8) || (auth==6 && password_size==64) {return -22;}
    let i=0;if password_size==64 {while i<64 {let c=load8(password+i);if !((c>=48 && c<=57) || (c>=65 && c<=70) || (c>=97 && c<=102)) {return -22;}i=i+1;}}
    i=0;while i<184 {store8(config+i,0);i=i+1;}i=0;while i<ssid_size {store8(config+i,load8(ssid+i));i=i+1;}
    i=0;while i<password_size {store8(config+32+i,load8(password+i));i=i+1;}
    esp32_store32(config+96,1);store8(config+116,157);esp32_store32(config+120,auth);store8(config+128,1);if auth==6 {store8(config+129,1);}esp32_store32(config+136,3);return 0;
}
fn esp_wifi_connect_attempt() {
    if !esp_wifi_initialized || !esp_wifi_started {return -19;}if esp_wifi_linked {return 0;}
    esp_wifi_connecting=1;esp_wifi_retry_at=0;esp_wifi_attempts=esp_wifi_attempts+1;esp_wifi_connect_until=esp_sdk_now()+20000000;
    let r=esp32_call32(esp32_external("esp_wifi_connect_internal"),0,0,0,0,0,0,0,0);esp_wifi_last_error=r;if r {esp_wifi_schedule_retry(esp_sdk_now());}return r;
}
fn esp_wifi_join(ssid,ssid_size,password,password_size,auth) {
    if !esp_wifi_initialized || !esp_wifi_started {return -19;}if esp_wifi_linked || esp_wifi_connecting {return -16;}
    let config=esp_sdk_calloc(1,184);if !config {return -12;}let r=esp_wifi_station_config(config,ssid,ssid_size,password,password_size,auth);
    if !r {r=esp32_call32(esp32_external("esp_wifi_set_config"),0,config,0,0,0,0,0,0);}
    let i=0;while i<184 {store8(config+i,0);i=i+1;}esp_sdk_free(config);if r {return r;}
    esp_wifi_reason=0;return esp_wifi_reconnect();
}
fn esp_wifi_reconnect() {
    if !esp_wifi_initialized || !esp_wifi_started {return -19;}if esp_wifi_connecting {return -16;}esp_wifi_want_link=1;esp_wifi_attempts=0;return esp_wifi_connect_attempt();
}
fn esp_wifi_disconnect() {
    esp_wifi_want_link=0;esp_wifi_retry_at=0;esp_wifi_connect_until=0;
    if !esp_wifi_initialized || !esp_wifi_started {return -19;}return esp32_call32(esp32_external("esp_wifi_disconnect_internal"),0,0,0,0,0,0,0,0);
}
fn esp_wifi_poll() {
    if !esp_wifi_want_link || !esp_wifi_started || esp_wifi_linked {return 0;}let now=esp_sdk_now();
    if esp_wifi_connecting && now>=esp_wifi_connect_until {
        let r=esp32_call32(esp32_external("esp_wifi_disconnect_internal"),0,0,0,0,0,0,0,0);esp_wifi_last_error= -110;esp_wifi_schedule_retry(now);if r {return r;}
    }
    if !esp_wifi_connecting && esp_wifi_retry_at && now>=esp_wifi_retry_at {return esp_wifi_connect_attempt();}return 0;
}
fn esp_wifi_frames_init() {
    if esp_wifi_rx_ring {return -16;}esp_wifi_rx_ring=esp_sdk_calloc(4,1544);if !esp_wifi_rx_ring {return -12;}return 0;
}
fn esp_wifi_rx_callback(buffer,size,eb,d,e,f,g,h) {
    let ps=esp32_irq_save();let accepted=esp_wifi_rx_ring && buffer && size>=14 && size<=1536 && esp_wifi_rx_count<4 && !esp_wifi_rx_busy;let out=0;
    if accepted {esp_wifi_rx_busy=1;let slot=esp_wifi_rx_head+esp_wifi_rx_count;if slot>=4 {slot=slot-4;}out=esp_wifi_rx_ring+slot*1544;}else {esp_wifi_rx_dropped=esp_wifi_rx_dropped+1;}esp32_irq_restore(ps);
    if accepted {let i=0;while i<size {store8(out+8+i,load8(buffer+i));i=i+1;}store64(out,size);ps=esp32_irq_save();esp_wifi_rx_count=esp_wifi_rx_count+1;esp_wifi_rx_busy=0;esp_wifi_rx_packets=esp_wifi_rx_packets+1;esp32_irq_restore(ps);}
    // The vendor free path takes a mutex and may yield: never call it masked.
    if eb {esp32_call32(esp32_external("esp_wifi_internal_free_rx_buffer"),eb,0,0,0,0,0,0,0);}return 0;
}
fn esp_wifi_receive(buffer,capacity) {
    if !buffer || capacity<0 {return -22;}if !esp_wifi_rx_count {return 0;}let packet=esp_wifi_rx_ring+esp_wifi_rx_head*1544;let size=load64(packet);if size>capacity {return -90;}
    let i=0;while i<size {store8(buffer+i,load8(packet+8+i));i=i+1;}let ps=esp32_irq_save();esp_wifi_rx_head=esp_wifi_rx_head+1;if esp_wifi_rx_head==4 {esp_wifi_rx_head=0;}esp_wifi_rx_count=esp_wifi_rx_count-1;esp32_irq_restore(ps);return size;
}
fn esp_wifi_transmit(buffer,size) {
    if !buffer || size<14 || size>1536 {return -22;}if !esp_wifi_initialized || !esp_wifi_started || !esp_wifi_linked {return -107;}
    let r=esp32_call32(esp32_external("esp_wifi_internal_tx"),0,buffer,size,0,0,0,0,0);if !r {esp_wifi_tx_packets=esp_wifi_tx_packets+1;}return r;
}
// Internal initialization leaves stage flags for rollback/retry after errors.
fn esp_wifi_station_setup() {
    let r=esp_wifi_frames_init();if r {return r;}r=esp_radio_os_init();if r {return r;}
    esp_radio_event_hook=esp32_callback(esp_wifi_event);esp32_store32(esp32_external("WIFI_EVENT"),"WIFI_EVENT");
    esp32_store32(0x3ff000cc,4294967295);esp32_store32(0x3ff48084,esp32_load32(0x3ff48084)&~(1<<17));esp32_call32(esp32_external("ets_delay_us"),10,0,0,0,0,0,0,0);esp32_store32(0x3ff48088,esp32_load32(0x3ff48088)&~(1<<28));
    let config=esp_sdk_calloc(1,160);if !config {return -12;}esp_wifi_init_config=config;esp32_store32(config,esp_radio_osi);let crypto=esp32_external("g_wifi_default_wpa_crypto_funcs");let i=0;while i<52 {store8(config+4+i,load8(crypto+i));i=i+1;}
    esp32_store32(config+56,4);esp32_store32(config+60,8);esp32_store32(config+64,1);esp32_store32(config+72,8);esp32_store32(config+80,5);esp32_store32(config+112,6);esp32_store32(config+120,752);esp32_store32(config+124,6);esp32_store32(config+144,3);esp32_store32(config+152,523190095);
    if esp_radio_nvs_table {esp32_store32(config+104,1);}
    esp_irq_enable();r=esp32_call32(esp32_external("esp_wifi_init_internal"),config,0,0,0,0,0,0,0);if r {return r;}esp_wifi_vendor_initialized=1;esp_wifi_initialized=1;
    r=esp32_call32(esp32_external("esp_wifi_set_storage"),1,0,0,0,0,0,0,0);if r {return r;}
    r=esp32_call32(esp32_external("esp_wifi_set_mode"),1,0,0,0,0,0,0,0);if r {return r;}
    r=esp32_call32(esp32_external("esp_supplicant_init"),0,0,0,0,0,0,0,0);if r {return r;}esp_wifi_supplicant=1;
    r=esp32_call32(esp32_external("esp_wifi_internal_reg_rxcb"),0,esp32_iram_callback32(esp_wifi_rx_callback),0,0,0,0,0,0);if r {return r;}
    r=esp32_call32(esp32_external("esp_wifi_start"),0,0,0,0,0,0,0,0);if r {return r;}esp_wifi_vendor_running=1;
    return esp32_call32(esp32_external("esp_wifi_set_ps"),0,0,0,0,0,0,0,0);
}
fn esp_wifi_stop_inner() {
    esp_wifi_want_link=0;esp_wifi_retry_at=0;esp_wifi_connect_until=0;
    if esp_wifi_vendor_running {let r=esp32_call32(esp32_external("esp_wifi_stop"),0,0,0,0,0,0,0,0);if r {return r;}esp_wifi_vendor_running=0;}
    esp_wifi_started=0;esp_wifi_linked=0;esp_wifi_connecting=0;esp_wifi_channel=0;esp_wifi_bssid=0;esp_wifi_rx_head=0;esp_wifi_rx_count=0;esp_wifi_generation=esp_wifi_generation+1;return 0;
}
fn esp_wifi_station_stop() {
    if !esp_wifi_vendor_initialized {return -19;}if esp_wifi_lifecycle_busy || (esp_wifi_control_task && esp_wifi_control_task!=esp_sdk_current) || esp32_load32(esp32_state()+16) || esp_sdk_timer_active {return -16;}
    esp_wifi_lifecycle_busy=1;let r=esp_wifi_stop_inner();esp_wifi_lifecycle_busy=0;esp_wifi_last_error=r;return r;
}
fn esp_wifi_station_start() {
    if !esp_wifi_vendor_initialized || !esp_wifi_supplicant {return -19;}if esp_wifi_lifecycle_busy || (esp_wifi_control_task && esp_wifi_control_task!=esp_sdk_current) || esp32_load32(esp32_state()+16) || esp_sdk_timer_active {return -16;}if esp_wifi_vendor_running {return 0;}
    esp_wifi_lifecycle_busy=1;let r=esp32_call32(esp32_external("esp_wifi_start"),0,0,0,0,0,0,0,0);if !r {esp_wifi_vendor_running=1;r=esp32_call32(esp32_external("esp_wifi_set_ps"),0,0,0,0,0,0,0,0);}esp_wifi_lifecycle_busy=0;esp_wifi_last_error=r;return r;
}
fn esp_wifi_teardown() {
    let r=esp_wifi_stop_inner();if r {return r;}
    if esp_wifi_vendor_initialized {r=esp32_call32(esp32_external("esp_wifi_deinit_internal"),0,0,0,0,0,0,0,0);if r {return r;}esp_wifi_vendor_initialized=0;}
    if esp_wifi_supplicant {r=esp32_call32(esp32_external("esp_supplicant_deinit"),0,0,0,0,0,0,0,0);if r {return r;}esp_wifi_supplicant=0;}
    let deadline=esp_sdk_now()+100000;r=esp_radio_resources_ready();while r && esp_sdk_now()<deadline {esp_sdk_delay(1);r=esp_radio_resources_ready();}if r {return r;}if esp_wifi_rx_busy {return -16;}
    // The pinned vendor library retains these lazy mutex pointers across its
    // deinit calls. All its tasks have exited: clear the references before
    // releasing their owned objects, so a later init creates fresh mutexes.
    esp32_store32(esp32_external("s_wifi_api_lock"),0);esp32_store32(esp32_external("g_wifi_global_lock"),0);esp32_store32(esp32_external("eloop_data_lock"),0);
    r=esp_radio_phy_release_buffers();if r {return r;}r=esp_radio_resources_end(esp32_callback(esp_radio_irq));if r {return r;}
    esp_sdk_free(esp_wifi_init_config);esp_sdk_free(esp_wifi_rx_ring);esp_wifi_init_config=0;esp_wifi_rx_ring=0;esp_wifi_initialized=0;esp_wifi_control_task=0;esp_wifi_attempts=0;esp_wifi_reason=0;
    esp_radio_isr=0;esp_radio_isr_arg=0;esp_radio_osi=0;esp_radio_event_hook=0;esp_radio_scan_done=0;esp_radio_scan_status= -1;return 0;
}
fn esp_wifi_station_deinit() {
    if esp_wifi_lifecycle_busy || (esp_wifi_control_task && esp_wifi_control_task!=esp_sdk_current) || esp32_load32(esp32_state()+16) || esp_sdk_timer_active || (esp_radio_owner && esp_radio_owner!=1) {return -16;}
    if !esp_radio_owner && !esp_wifi_initialized && !esp_wifi_rx_ring && !esp_radio_osi {return 0;}
    esp_wifi_lifecycle_busy=1;let r=esp_wifi_teardown();esp_wifi_lifecycle_busy=0;esp_wifi_cleanup_error=r;return r;
}
fn esp_wifi_station_init() {
    if esp_wifi_lifecycle_busy || esp_wifi_initialized || esp_radio_osi || esp_wifi_rx_ring || esp_radio_owner || esp_irq_handler(0) {return -16;}
    if !esp_sdk_current {return -19;}if esp32_load32(esp32_state()+16) || esp_sdk_timer_active {return -16;}
    esp_wifi_lifecycle_busy=1;esp_wifi_cleanup_error=0;let r=esp_radio_resources_begin(1);
    if !r {esp_wifi_control_task=esp_sdk_current;r=esp_wifi_station_setup();if r {esp_wifi_cleanup_error=esp_wifi_teardown();}}
    esp_wifi_lifecycle_busy=0;esp_wifi_last_error=r;return r;
}
