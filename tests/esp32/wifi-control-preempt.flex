import "../../lib/platform/esp32-xip.flex";
import "../../lib/platform/esp32-sdk-preempt.flex";
import "../../lib/platform/esp32-wifi.flex";
global ct_expect_hooks=0;
global ct_ref=0;
global ct_event_data=0;
global ct_seen_retry=0;
global ct_mode=0;
global ct_phase=0;
global ct_armed=0;
global ct_done=0;
global ct_peer_done=0;
global ct_hooks=0;
global ct_masked=0;
global ct_actor_result=0;
global ct_peer_result=0;
global ct_checks=0;
global ct_error=0;
fn ct_get(i) {return esp32_load32(ct_ref+i*4);}
fn ct_set(i,v) {esp32_store32(ct_ref+i*4,v);return 0;}
fn ct_track_event(id) {let r=esp_wifi_event(id);ct_seen_retry=esp_wifi_retry_at;return r;}
fn ct_emit(id) {return esp32_call32(esp32_external("wifi_control_emit"),id,0,0,0,0,0,0,0);}
fn ct_check(ok,code) {ct_checks=ct_checks+1;if !ok && !ct_error {ct_error=code;esp_uart_write("WIFI CONTROL FAIL ");esp_uart_hex(code);esp_uart_write(" mode/bad=");esp_uart_hex(ct_mode);esp_uart_hex(ct_get(2));esp_uart_write(" actor/peer=");esp_uart_hex(ct_actor_result);esp_uart_hex(ct_peer_result);esp_uart_write("\r\n");}return ok;}
fn ct_soft(source) {
    if ct_mode==20 {ct_check(esp_wifi_join("test",4,"testpass",8,3)== -16 && esp_wifi_reconnect()== -16 && esp_wifi_connect_attempt()== -16 && esp_wifi_disconnect()== -16 && esp_wifi_poll()== -16,220);ct_phase=20;}else {esp_sdk_reschedule_request();}return 0;
}
fn ct_gate(point) {
    if !ct_armed || point!=ct_mode {return 0;}ct_armed=0;ct_hooks=ct_hooks+1;ct_phase=point;let ps=esp32_irq_save();if ps&15 {ct_masked=ct_masked+1;}esp32_irq_restore(ps);esp32_irq_raise(128);
    if !(ps&15) {let begin=esp32_cycles();while !ct_peer_done && ((esp32_cycles()-begin)&4294967295)<8000000 {}}return 0;
}
fn ct_reject() {
    let want=esp_wifi_want_link;let attempts=esp_wifi_attempts;let retry=esp_wifi_retry_at;let deadline=esp_wifi_connect_until;
    let ok=esp_wifi_join("test",4,"testpass",8,3)== -16 && esp_wifi_reconnect()== -16 && esp_wifi_connect_attempt()== -16 && esp_wifi_disconnect()== -16 && esp_wifi_poll()== -16 && esp_wifi_station_stop()== -16 && esp_wifi_station_deinit()== -16 && esp_wifi_station_start()== -16;
    return ok && want==esp_wifi_want_link && attempts==esp_wifi_attempts && retry==esp_wifi_retry_at && deadline==esp_wifi_connect_until && !ct_get(10) && !ct_get(11) && !ct_get(18);
}
fn ct_zero() {let p=ct_get(19);if !p {return 0;}let i=0;while i<184 {if load8(p+i) {return 0;}i=i+1;}return 1;}
fn ct_actor(a,b,c,d,e,f,g,h) {
    if ct_mode==1 {ct_actor_result=esp_wifi_join("test",4,"testpass",8,3);}
    if ct_mode==2 || ct_mode==6 {ct_actor_result=esp_wifi_reconnect();}
    if ct_mode==3 {ct_actor_result=esp_wifi_disconnect();}
    if ct_mode==4 || ct_mode==5 || ct_mode==7 {ct_actor_result=esp_wifi_poll();}
    if ct_mode==8 {esp_radio_event_data=ct_event_data;esp_radio_event_size=40;ct_actor_result=esp_wifi_event(4);esp_radio_event_data=0;esp_radio_event_size=0;}
    if ct_mode==9 {ct_actor_result=esp_wifi_retry_policy(20,30,4);}
    if ct_mode==10 {ct_actor_result=esp_wifi_schedule_retry(100000);}
    if ct_mode==11 {ct_actor_result=esp_wifi_join("test",4,"testpass",8,3);}
    ct_done=1;return 0;
}
fn ct_peer(a,b,c,d,e,f,g,h) {
    while !ct_phase && !ct_get(24) && !ct_done {}
    ct_peer_result=0;if ct_mode<=5 || (ct_expect_hooks && (ct_mode==6 || ct_mode==7 || ct_mode==11)) {if !ct_reject() {ct_peer_result= -5;}}
    if ct_mode==8 {if !esp_wifi_linked || esp_wifi_connecting || esp_wifi_attempts || esp_wifi_retry_at || esp_wifi_connect_until || esp_wifi_channel!=6 || esp_wifi_bssid!=0xb200000000a1 {ct_peer_result= -5;}}
    if ct_mode==9 {if esp_wifi_retry_base!=20 || esp_wifi_retry_max!=30 || esp_wifi_retry_limit!=4 {ct_peer_result= -5;}}
    if ct_mode==10 {if esp_wifi_retry_at!=120000 || esp_wifi_connecting || esp_wifi_connect_until {ct_peer_result= -5;}}
    ct_peer_done=1;ct_set(25,1);return 0;
}
fn ct_join(t) {while load64(t+544)!=2 {esp_sdk_yield();}return esp_sdk_task_reap(t);}
fn ct_reset() {
    let i=0;while i<32 {ct_set(i,0);i=i+1;}ct_set(4,esp32_callback32(esp_event_post));esp_radio_event_hook=esp32_callback(ct_track_event);
    esp_wifi_initialized=1;esp_wifi_vendor_initialized=1;esp_wifi_vendor_running=1;esp_wifi_supplicant=1;esp_wifi_started=1;esp_wifi_linked=0;esp_wifi_connecting=0;esp_wifi_want_link=1;esp_wifi_attempts=0;esp_wifi_retry_at=0;esp_wifi_connect_until=0;esp_wifi_last_error=0;esp_wifi_reason=0;esp_wifi_channel=0;esp_wifi_bssid=0;esp_wifi_control_task=0;esp_wifi_retry_policy(10,25,2);
    ct_phase=0;ct_armed=0;ct_done=0;ct_peer_done=0;ct_actor_result= -99;ct_peer_result= -99;return 0;
}
fn main() {
    if esp_sdk_heap_init(0x3ffc8000,98304) || esp_sdk_task_init() {return 1;}esp_irq_enable();ct_ref=esp32_external("wifi_control_peer");ct_event_data=alloc(40);store8(ct_event_data+33,0xa1);store8(ct_event_data+38,0xb2);store8(ct_event_data+39,6);ct_gate(0);
    if esp_irq_software(esp32_callback(ct_soft)) || esp_sdk_preempt_start(5000) {return 2;}let baseline=esp_sdk_heap_free();ct_mode=1;
    while ct_mode<=11 {
        esp_uart_write("CONTROL CASE ");esp_uart_hex(ct_mode);esp_uart_write("\r\n");ct_reset();
        if ct_mode==1 {ct_set(12,1);}if ct_mode==2 || ct_mode==4 {ct_set(13,1);}if ct_mode==3 || ct_mode==5 {ct_set(14,1);}
        if ct_mode==4 || ct_mode==7 {esp_wifi_retry_at=1;}if ct_mode==5 {esp_wifi_connecting=1;esp_wifi_connect_until=1;esp_wifi_attempts=1;}
        if ct_mode==8 {esp_wifi_connecting=1;esp_wifi_attempts=1;esp_wifi_retry_at=1;esp_wifi_connect_until=1;}
        if ct_mode==10 {esp_wifi_retry_policy(10,25,4);esp_wifi_connecting=1;esp_wifi_connect_until=1;esp_wifi_attempts=2;}
        ct_armed=1;let setup_ps=esp32_irq_save();let peer=esp_sdk_task_create(esp32_callback32(ct_peer),0,8192,5);let actor=esp_sdk_task_create(esp32_callback32(ct_actor),0,8192,5);esp32_irq_restore(setup_ps);if !peer || !actor {return 3;}ct_join(actor);ct_join(peer);
        let ok=!ct_actor_result && !ct_peer_result && !ct_get(2) && !esp_wifi_control_active;
        if ct_mode==1 || ct_mode==11 {ok=ok && ct_get(1)==1 && ct_get(3)==1 && ct_zero();}
        if ct_mode==1 || ct_mode==2 || ct_mode==4 || ct_mode==6 || ct_mode==7 || ct_mode==11 {ok=ok && esp_wifi_connecting && esp_wifi_attempts==1 && !esp_wifi_retry_at && esp_wifi_connect_until>esp_sdk_now();}
        if ct_mode==3 {ok=ok && !esp_wifi_want_link && !esp_wifi_connecting && !esp_wifi_retry_at && !esp_wifi_connect_until && ct_get(5)==1;}
        if ct_mode==5 {ok=ok && !esp_wifi_connecting && esp_wifi_retry_at>esp_sdk_now() && ct_get(5)==1 && !ct_get(3) && esp_wifi_last_error== -110;}
        if ct_mode==8 {ok=ok && esp_wifi_linked && esp_wifi_channel==6 && !esp_wifi_connecting && !esp_wifi_attempts;}
        if ct_mode==9 {ok=ok && esp_wifi_retry_base==20 && esp_wifi_retry_max==30 && esp_wifi_retry_limit==4;}
        if ct_mode==10 {ok=ok && esp_wifi_retry_at==120000;}
        ct_check(ok,100+ct_mode);if ct_error {return ct_error;}if ct_expect_hooks && ct_mode>=6 {ct_check(!ct_armed,200+ct_mode);}
        ct_check(esp_sdk_heap_free()==baseline,300+ct_mode);if ct_error {return ct_error;}ct_mode=ct_mode+1;
    }
    // A newer connected/disconnected/stopped event controls state even when the
    // older synchronous vendor call returns an error or success afterward.
    ct_mode=30;ct_reset();ct_set(8,17);ct_set(16,4);ct_check(esp_wifi_reconnect()==17 && esp_wifi_linked && !esp_wifi_connecting && !esp_wifi_retry_at && !esp_wifi_last_error && !esp_wifi_attempts,401);
    ct_reset();ct_set(8,17);ct_set(16,5);ct_check(esp_wifi_reconnect()==17 && !esp_wifi_linked && !esp_wifi_connecting && esp_wifi_retry_at>esp_sdk_now() && esp_wifi_reason==201 && !esp_wifi_last_error && esp_wifi_attempts==1,402);
    ct_reset();ct_set(16,3);ct_check(!esp_wifi_reconnect() && !esp_wifi_started && !esp_wifi_connecting && !esp_wifi_connect_until && !esp_wifi_retry_at,403);
    ct_reset();esp_wifi_connecting=1;esp_wifi_connect_until=1;esp_wifi_attempts=1;ct_set(17,4);ct_check(!esp_wifi_poll() && esp_wifi_linked && !esp_wifi_retry_at && !esp_wifi_last_error && !ct_get(3),404);
    ct_reset();ct_set(9,23);ct_set(17,4);ct_check(esp_wifi_disconnect()==23 && esp_wifi_linked && !esp_wifi_last_error && !esp_wifi_want_link,405);
    ct_reset();esp_wifi_connecting=1;esp_wifi_connect_until=1;esp_wifi_attempts=2;ct_set(17,5);ct_check(!esp_wifi_poll() && !esp_wifi_want_link && esp_wifi_last_error== -110 && !esp_wifi_retry_at && !ct_get(3),406);
    ct_reset();esp_wifi_retry_policy(1000,1000,4);esp_wifi_connecting=1;esp_wifi_connect_until=1;esp_wifi_attempts=1;ct_set(17,5);ct_set(21,1);ct_check(!esp_wifi_poll() && esp_wifi_retry_at==ct_seen_retry && esp_wifi_retry_at>esp_sdk_now() && !ct_get(3),417);
    ct_reset();ct_set(0,42);ct_check(esp_wifi_join("test",4,"testpass",8,3)==42 && !ct_get(3) && !esp_wifi_control_active && ct_zero() && esp_sdk_heap_free()==baseline,407);
    ct_reset();ct_check(esp_wifi_join("t",1,"bad",3,3)== -22 && !ct_get(1) && !esp_wifi_control_active && esp_sdk_heap_free()==baseline,408);
    let held=esp_sdk_malloc(baseline-128);if !held {return 4;}let free=esp_sdk_heap_free();ct_check(esp_wifi_join("test",4,"testpass",8,3)== -12 && !esp_wifi_control_active && esp_sdk_heap_free()==free,409);esp_sdk_free(held);if ct_error {return ct_error;}
    // Backoff origin follows the completed disconnect call, not the stale
    // timestamp sampled before a slow vendor frame.
    ct_reset();ct_set(20,1);esp_wifi_connecting=1;esp_wifi_connect_until=1;esp_wifi_attempts=1;let begin=esp_sdk_now();ct_check(!esp_wifi_poll() && esp_wifi_retry_at>=begin+10000 && esp_wifi_retry_at>esp_sdk_now() && !ct_get(3),410);
    ct_mode=20;ct_reset();let ps=esp32_irq_save();ct_check(esp_wifi_disconnect()== -16 && esp_wifi_reconnect()== -16 && esp_wifi_poll()== -16 && esp_wifi_want_link,411);esp32_irq_restore(ps);esp32_irq_raise(128);begin=esp32_cycles();while ct_phase!=20 && ((esp32_cycles()-begin)&4294967295)<1000000 {}ct_check(ct_phase==20 && !ct_get(1) && !ct_get(3) && !ct_get(5),412);
    esp_wifi_lifecycle_busy=1;ct_check(esp_wifi_disconnect()== -16 && esp_wifi_reconnect()== -16 && esp_wifi_poll()== -16 && esp_wifi_want_link,413);esp_wifi_lifecycle_busy=0;ct_check(!esp_wifi_station_deinit() && !esp_wifi_control_active && esp_sdk_heap_free()==baseline,414);
    if ct_expect_hooks {ct_check(ct_hooks==6 && ct_masked==5,415);}ct_check(!esp_sdk_preempt_stop(),416);if ct_error {return ct_error;}
    esp_uart_write("PASS: Wi-Fi control lease, inline event generation, credential cleanup and atomic retry state; checks=");esp_uart_hex(ct_checks);esp_uart_write(" hooks=");esp_uart_hex(ct_hooks);esp_uart_write(" masked=");esp_uart_hex(ct_masked);esp_uart_write("\r\n");return 0;
}
