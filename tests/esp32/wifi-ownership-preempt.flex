import "../../lib/platform/esp32-xip.flex";
import "../../lib/platform/esp32-sdk-preempt.flex";
import "../../lib/platform/esp32-wifi.flex";
global wc_expect_hooks=0;
global wc_ref=0;
global wc_mode=0;
global wc_phase=0;
global wc_armed=0;
global wc_hooks=0;
global wc_masked=0;
global wc_done=0;
global wc_peer_done=0;
global wc_actor_result=0;
global wc_peer_result=0;
global wc_a=0;
global wc_b=0;
global wc_c=0;
global wc_out=0;
global wc_peer_out=0;
global wc_checks=0;
global wc_error=0;
fn wc_get(i) {return esp32_load32(wc_ref+i*4);}
fn wc_set(i,v) {esp32_store32(wc_ref+i*4,v);return 0;}
fn wc_check(ok,code) {wc_checks=wc_checks+1;if !ok && !wc_error {wc_error=code;esp_uart_write("WIFI OWNERSHIP FAIL ");esp_uart_hex(code);esp_uart_write(" mode/bad=");esp_uart_hex(wc_mode);esp_uart_hex(wc_get(2));esp_uart_write(" actor/peer=");esp_uart_hex(wc_actor_result);esp_uart_hex(wc_peer_result);esp_uart_write("\r\n");}return ok;}
fn wc_fill(p,marker) {let i=0;while i<1536 {store8(p+i,(i*7+marker)&255);i=i+1;}return 0;}
fn wc_bytes(p,marker,size) {let i=0;while i<size {if load8(p+i)!=((i*7+marker)&255) {return 0;}i=i+1;}return 1;}
fn wc_callback(p,size,eb) {return esp_wifi_rx_callback(p,size,eb,0,0,0,0,0);}
fn wc_reject() {if esp_wifi_station_stop()!= -16 || esp_wifi_station_deinit()!= -16 || wc_get(4) || wc_get(17) {return -5;}return 0;}
fn wc_soft(source) {
    if wc_mode==20 {wc_check(esp_wifi_transmit(wc_a,14)== -16 && esp_wifi_receive(wc_out,1536)== -16 && esp_wifi_frames_init()== -16,220);wc_phase=20;}else {esp_sdk_reschedule_request();}return 0;
}
fn wc_gate(point) {
    if !wc_armed || point!=wc_mode {return 0;}wc_armed=0;wc_hooks=wc_hooks+1;wc_phase=point;let ps=esp32_irq_save();if ps&15 {wc_masked=wc_masked+1;}esp32_irq_restore(ps);esp32_irq_raise(128);
    if !(ps&15) {let begin=esp32_cycles();while !wc_peer_done && ((esp32_cycles()-begin)&4294967295)<8000000 {}}return 0;
}
fn wc_actor(a,b,c,d,e,f,g,h) {
    if wc_mode==1 || wc_mode==10 || wc_mode==11 {wc_actor_result=esp_wifi_transmit(wc_a,1536);}
    if wc_mode==2 || wc_mode==9 {wc_actor_result=wc_callback(wc_a,14,0x1234);}
    if wc_mode==3 || wc_mode==12 {wc_actor_result=esp_wifi_receive(wc_out,1536);}
    if wc_mode==4 {wc_actor_result=esp_wifi_receive(wc_out,1536);}
    if wc_mode==5 {wc_actor_result=wc_callback(wc_b,1536,0x1234);}
    if wc_mode==6 {wc_actor_result=esp_wifi_station_deinit();}
    if wc_mode==7 {wc_actor_result=esp_wifi_station_stop();}
    if wc_mode==8 {wc_actor_result=esp_wifi_frames_init();}
    if wc_mode==13 {wc_actor_result=wc_callback(wc_b,14,0);}
    wc_done=1;wc_set(26,1);return 0;
}
fn wc_peer(a,b,c,d,e,f,g,h) {
    while !wc_phase && !wc_get(24) && !wc_done {}
    wc_peer_result=0;
    if wc_mode==1 {wc_peer_result=wc_reject();wc_set(0,42);if esp_wifi_transmit(wc_b,1536)!=42 || esp_wifi_tx_active!=1 {wc_peer_result= -5;}}
    if wc_mode==2 {wc_peer_result=wc_reject();if esp_wifi_receive(wc_peer_out,1536)!=14 || !wc_bytes(wc_peer_out,1,14) {wc_peer_result= -5;}}
    if wc_mode==3 || wc_mode==4 {
        if wc_expect_hooks {wc_peer_result=wc_reject();if esp_wifi_receive(wc_peer_out,1536)!= -16 {wc_peer_result= -5;}}
        let size=14;if wc_mode==4 {size=1536;}if wc_callback(wc_b,size,0) {wc_peer_result= -5;}
    }
    if wc_mode==5 {if wc_expect_hooks {wc_peer_result=wc_reject();}if esp_wifi_receive(wc_peer_out,1536)!=14 || !wc_bytes(wc_peer_out,1,14) {wc_peer_result= -5;}if wc_expect_hooks {wc_callback(wc_c,14,0);}}
    if wc_mode==6 {
        if wc_expect_hooks {if esp_wifi_transmit(wc_b,14)!= -16 || esp_wifi_receive(wc_peer_out,1536)!= -16 || esp_wifi_frames_init()!= -16 || esp_wifi_station_deinit()!= -16 {wc_peer_result= -5;}}
        else {if esp_wifi_transmit(wc_b,14)!= -107 || esp_wifi_receive(wc_peer_out,1536) {wc_peer_result= -5;}}
        wc_callback(wc_b,14,0);
    }
    if wc_mode==7 {wc_set(25,1);wc_peer_result=wc_callback(wc_b,14,0x1234);}
    if wc_mode==8 {wc_peer_result=esp_wifi_frames_init();}
    if wc_mode==9 || wc_mode==10 {if wc_expect_hooks {wc_peer_result=wc_reject();}}
    if wc_mode==11 {wc_peer_result=esp_wifi_transmit(wc_b,1536);}
    if wc_mode==12 {wc_peer_result=wc_callback(wc_b,14,0);}
    if wc_mode==13 {if esp_wifi_receive(wc_peer_out,1536)!=14 || !wc_bytes(wc_peer_out,1,14) {wc_peer_result= -5;}}
    wc_peer_done=1;wc_set(25,1);return 0;
}
fn wc_join(t) {while load64(t+544)!=2 {esp_sdk_yield();}return esp_sdk_task_reap(t);}
fn wc_reset() {
    let i=0;while i<32 {wc_set(i,0);i=i+1;}wc_phase=0;wc_armed=0;wc_done=0;wc_peer_done=0;wc_actor_result= -99;wc_peer_result= -99;
    esp_wifi_initialized=1;esp_wifi_vendor_initialized=1;esp_wifi_vendor_running=1;esp_wifi_started=1;esp_wifi_linked=1;esp_wifi_control_task=0;
    esp_wifi_rx_head=0;esp_wifi_rx_count=0;esp_wifi_rx_dropped=0;esp_wifi_rx_packets=0;esp_wifi_tx_packets=0;return 0;
}
fn main() {
    if esp_sdk_heap_init(0x3ffc8000,98304) || esp_sdk_task_init() {return 1;}esp_irq_enable();wc_ref=esp32_external("wifi_packet_peer");wc_a=alloc(1536);wc_b=alloc(1536);wc_c=alloc(1536);wc_out=alloc(1544);wc_peer_out=alloc(1544);store64(wc_out+1536,0x12345678);wc_fill(wc_a,1);wc_fill(wc_b,2);wc_fill(wc_c,3);wc_gate(0);
    if esp_irq_software(esp32_callback(wc_soft)) || esp_sdk_preempt_start(5000) {return 2;}let baseline=esp_sdk_heap_free();wc_mode=1;
    while wc_mode<=13 {
        esp_uart_write("WIFI CASE ");esp_uart_hex(wc_mode);esp_uart_write("\r\n");wc_reset();if wc_mode!=8 && esp_wifi_frames_init() {return 3;}
        if wc_mode==1 {wc_set(12,1);}if wc_mode==2 {wc_set(13,1);}if wc_mode==7 {wc_set(13,1);wc_set(14,1);wc_set(15,1);}
        if wc_mode==3 || wc_mode==5 || wc_mode==12 || wc_mode==13 {wc_callback(wc_a,14,0);}if wc_mode==4 {wc_callback(wc_a,1536,0);}
        wc_armed=1;
        // Publish both dependent workers before either can starve main.
        let setup_ps=esp32_irq_save();let peer=esp_sdk_task_create(esp32_callback32(wc_peer),0,8192,5);let actor=esp_sdk_task_create(esp32_callback32(wc_actor),0,8192,5);esp32_irq_restore(setup_ps);if !peer || !actor {return 4;}wc_join(actor);wc_join(peer);
        let ok=!wc_actor_result && !wc_peer_result;
        if wc_mode==1 {ok=ok && wc_get(1)==2 && esp_wifi_tx_packets==1 && !wc_get(4) && !wc_get(17);}
        if wc_mode==2 {ok=ok && wc_get(3)==1 && !esp_wifi_rx_count && !wc_get(4) && !wc_get(17);}
        if wc_mode==3 || wc_mode==4 || wc_mode==12 {let size=14;if wc_mode==4 {size=1536;}ok=wc_actor_result==size && !wc_peer_result && wc_bytes(wc_out,1,size) && esp_wifi_rx_count==1 && esp_wifi_receive(wc_out,1536)==size && wc_bytes(wc_out,2,size);}
        if wc_mode==5 {let dropped=0;if wc_expect_hooks {dropped=1;}ok=ok && esp_wifi_rx_count==1 && esp_wifi_rx_dropped==dropped && esp_wifi_receive(wc_out,1536)==1536 && wc_bytes(wc_out,2,1536);}
        if wc_mode==6 {ok=ok && !esp_wifi_rx_ring && !esp_wifi_rx_count && !esp_wifi_initialized && wc_get(4)==1 && wc_get(17)==1;}
        if wc_mode==7 {ok=wc_actor_result== -16 && !wc_peer_result && !esp_wifi_vendor_running && !esp_wifi_started && !esp_wifi_rx_count && esp_wifi_rx_dropped==1 && !esp_wifi_rx_packets && wc_get(4)==1 && !wc_get(17) && wc_get(3)==1;}
        if wc_mode==8 {ok=!wc_actor_result && wc_peer_result== -16 && esp_wifi_rx_ring;}
        if wc_mode==9 {ok=ok && esp_wifi_rx_count==1 && wc_get(3)==1 && !wc_get(4) && !wc_get(17);}
        if wc_mode==10 {ok=ok && esp_wifi_tx_packets==1 && wc_get(1)==1 && !wc_get(4) && !wc_get(17);}
        if wc_mode==11 {ok=ok && esp_wifi_tx_packets==2 && wc_get(1)==2;}
        if wc_mode==13 {ok=ok && esp_wifi_rx_count==1 && esp_wifi_receive(wc_out,1536)==14 && wc_bytes(wc_out,2,14);}
        wc_check(ok && !wc_get(2) && !esp_wifi_packets_active() && load64(wc_out+1536)==0x12345678,100+wc_mode);if wc_error {return wc_error;}
        if wc_expect_hooks && wc_mode>=3 && wc_mode!=7 {wc_check(!wc_armed,200+wc_mode);}if wc_mode==7 {wc_check(!esp_wifi_station_stop() && wc_get(4)==1,207);}
        wc_check(!esp_wifi_station_deinit() && !esp_wifi_rx_ring && !esp_wifi_initialized && !esp_wifi_lifecycle_busy && !esp_wifi_packets_active() && esp_sdk_heap_free()==baseline,300+wc_mode);if wc_error {return wc_error;}wc_mode=wc_mode+1;
    }
    wc_mode=20;wc_reset();if esp_wifi_frames_init() {return 5;}let calls=wc_get(1);let ps=esp32_irq_save();wc_check(esp_wifi_transmit(wc_a,14)== -16,220);esp32_irq_restore(ps);esp32_irq_raise(128);let begin=esp32_cycles();while wc_phase!=20 && ((esp32_cycles()-begin)&4294967295)<1000000 {}wc_check(wc_phase==20 && wc_get(1)==calls,221);
    wc_set(0,55);wc_check(esp_wifi_transmit(wc_a,14)==55 && !esp_wifi_tx_packets && !esp_wifi_tx_active,222);wc_check(esp_wifi_transmit(0,14)== -22 && esp_wifi_transmit(wc_a,1537)== -22 && esp_wifi_receive(0,14)== -22 && !esp_wifi_packets_active(),223);
    ps=esp32_irq_save();esp_wifi_lifecycle_busy=1;esp32_irq_restore(ps);wc_check(esp_wifi_transmit(wc_a,14)== -16 && esp_wifi_receive(wc_out,1536)== -16,224);wc_callback(wc_a,14,0x1234);esp_wifi_lifecycle_busy=0;wc_check(!esp_wifi_rx_count && esp_wifi_rx_dropped==1 && wc_get(3)==1 && !esp_wifi_rx_callbacks && !wc_get(2),225);
    wc_check(!esp_wifi_station_deinit() && esp_sdk_heap_free()==baseline,226);let held=esp_sdk_malloc(baseline-5000);if !held {return 6;}let free=esp_sdk_heap_free();wc_check(esp_wifi_frames_init()== -12 && !esp_wifi_rx_ring && esp_sdk_heap_free()==free,227);esp_sdk_free(held);
    if wc_expect_hooks {wc_check(wc_hooks==10 && wc_masked==8,228);}wc_check(!esp_sdk_preempt_stop(),229);if wc_error {return wc_error;}
    esp_uart_write("PASS: Wi-Fi concurrent C TX/free leases, RX FIFO/consumer ownership and retriable teardown; checks=");esp_uart_hex(wc_checks);esp_uart_write(" hooks=");esp_uart_hex(wc_hooks);esp_uart_write(" masked=");esp_uart_hex(wc_masked);esp_uart_write("\r\n");return 0;
}
