import "../../lib/platform/esp32-xip.flex";
import "../../lib/platform/esp32-sdk-preempt.flex";
import "../../lib/platform/esp32-bluetooth.flex";
global bt_expect_hooks=0;
global bt_ref=0;
global bt_mode=0;
global bt_phase=0;
global bt_armed=0;
global bt_hooks=0;
global bt_masked=0;
global bt_done=0;
global bt_peer_done=0;
global bt_actor_result=0;
global bt_peer_result=0;
global bt_packet=0;
global bt_other=0;
global bt_hnc=0;
global bt_wire=0;
global bt_checks=0;
global bt_error=0;
fn bt_check(ok,code) {bt_checks=bt_checks+1;if !ok && !bt_error {bt_error=code;esp_uart_write("BT CONCURRENT FAIL ");esp_uart_hex(code);esp_uart_write(" mode=");esp_uart_hex(bt_mode);esp_uart_write(" actor/peer=");esp_uart_hex(bt_actor_result);esp_uart_hex(bt_peer_result);esp_uart_write("\r\n");}return ok;}
fn bt_set(i,value) {esp32_store32(bt_ref+i*4,value);return 0;}
fn bt_get(i) {return esp32_load32(bt_ref+i*4);}
fn bt_emit(op,status,credits) {return esp32_call32(esp32_external("bt_concurrent_emit"),op,status,credits,0,0,0,0,0);}
fn bt_soft(source) {
    if bt_mode==9 {
        bt_check(esp_bt_hci_send_packet(bt_packet,21)== -16 && esp_bt_hci_command(0x1001,0,0)== -16 && esp_bt_transport_init()== -16 && esp_bt_transport_release()== -16,909);bt_phase=1;
    }else {esp_sdk_reschedule_request();}return 0;
}
fn bt_gate(point) {
    if !bt_armed || point!=bt_mode {return 0;}bt_armed=0;bt_hooks=bt_hooks+1;bt_phase=point;let ps=esp32_irq_save();if ps&15 {bt_masked=bt_masked+1;}esp32_irq_restore(ps);esp32_irq_raise(128);
    if !(ps&15) {let begin=esp32_cycles();while !bt_peer_done && ((esp32_cycles()-begin)&4294967295)<8000000 {}}return 0;
}
fn bt_peer(a,b,c,d,e,f,g,h) {
    while !bt_phase && !bt_get(24) && !bt_done {}
    if bt_mode==1 {bt_peer_result=esp_bt_transport_init();}
    if bt_mode==2 {bt_peer_result=esp_bt_hci_command(0x1001,0,0);}
    if bt_mode==3 {bt_peer_result=esp_bt_transport_release();}
    if bt_mode==4 {let p=esp_sdk_malloc(6000);if !p {bt_peer_result= -12;}else {let i=0;while i<6000 {store8(p+i,0xa5);i=i+1;}bt_emit(0xffff,0,1);i=0;bt_peer_result=0;while i<6000 {if load8(p+i)!=0xa5 {bt_peer_result= -5;}i=i+1;}esp_sdk_free(p);}}
    if bt_mode==5 || bt_mode==6 {
        bt_peer_result=0;if !esp_bt_tx_active || esp_bt_hci_send_packet(bt_other,21)!= -11 || esp_bt_hci_send_packet(bt_hnc,9)!= -11 || esp_bt_transport_release()!= -16 || esp_bt_controller_deinit()!= -16 {bt_peer_result= -5;}
    }
    if bt_mode==7 {bt_set(7,0x55);bt_peer_result=esp_bt_hci_command(0x1002,0,0);}
    if bt_mode==8 {bt_peer_result=0;if bt_get(1) || esp_bt_tx_active || esp_bt_cmd_pending || !esp_bt_cmd_busy {bt_peer_result= -5;}bt_emit(0,0,1);}
    bt_peer_done=1;bt_set(25,1);return 0;
}
fn bt_actor(a,b,c,d,e,f,g,h) {
    if bt_mode==1 {bt_actor_result=esp_bt_transport_init();}
    if bt_mode==2 || bt_mode==7 || bt_mode==8 {bt_actor_result=esp_bt_hci_command(0x1001,0,0);}
    if bt_mode==3 {bt_actor_result=bt_emit(0xffff,0,1);}
    if bt_mode==4 {bt_actor_result=esp_bt_transport_release();}
    if bt_mode==5 || bt_mode==6 {bt_actor_result=esp_bt_hci_send_packet(bt_packet,21);}
    bt_done=1;return 0;
}
fn bt_reset() {
    let i=0;while i<32 {bt_set(i,0);i=i+1;}bt_set(0,1);bt_set(4,esp32_callback32(esp_bt_send_ready));bt_set(5,esp32_callback32(esp_bt_recv));bt_set(23,1);bt_phase=0;bt_armed=1;bt_done=0;bt_peer_done=0;bt_actor_result= -99;bt_peer_result= -99;return 0;
}
fn bt_join(t) {while load64(t+544)!=2 {esp_sdk_yield();}return esp_sdk_task_reap(t);}
fn main() {
    if esp_sdk_heap_init(0x3ffc8000,98304) || esp_sdk_task_init() {return 1;}esp_irq_enable();bt_ref=esp32_external("bt_concurrent");bt_packet=alloc(24);bt_other=alloc(24);bt_hnc=alloc(16);bt_wire=alloc(16);bt_gate(0);
    store8(bt_packet,2);store8(bt_other,2);store8(bt_packet+1,64);store8(bt_other+1,64);store8(bt_packet+2,0);store8(bt_other+2,0);store8(bt_packet+3,16);store8(bt_other+3,16);let i=5;while i<21 {store8(bt_packet+i,0x41);store8(bt_other+i,0x62);i=i+1;}
    store8(bt_hnc,1);store8(bt_hnc+1,0x35);store8(bt_hnc+2,0x0c);store8(bt_hnc+3,5);store8(bt_hnc+4,1);store8(bt_hnc+5,64);store8(bt_hnc+7,1);
    if esp_irq_software(esp32_callback(bt_soft)) || esp_sdk_preempt_start(5000) {return 2;}let baseline=esp_sdk_heap_free();bt_mode=1;
    // Publish dependent peers before a higher-priority worker can starve main.
    while bt_mode<=8 {
        esp_uart_write("BT CASE ");esp_uart_hex(bt_mode);esp_uart_write("\r\n");bt_reset();if bt_mode!=1 && esp_bt_transport_init() {return 3;}
        if bt_mode==2 {bt_set(12,1);}if bt_mode==5 {bt_set(12,1);}if bt_mode==6 {bt_set(11,1);bt_set(13,1);}if bt_mode==5 || bt_mode==6 {esp_bt_vendor_initialized=1;}if bt_mode==7 {bt_set(7,0x22);}
        if bt_mode==8 {bt_set(7,0x22);bt_set(8,0x33);bt_set(9,0x1001);bt_set(23,0);}
        let setup_ps=esp32_irq_save();let peer=esp_sdk_task_create(esp32_callback32(bt_peer),0,8192,5);let actor=esp_sdk_task_create(esp32_callback32(bt_actor),0,8192,5);esp32_irq_restore(setup_ps);if !peer || !actor {return 4;}
        bt_join(actor);bt_join(peer);
        if bt_mode==1 {bt_check(!bt_actor_result && bt_peer_result== -16,101);}
        if bt_mode==2 {bt_check(!bt_actor_result && bt_peer_result== -16 && bt_get(1)==1,102);}
        if bt_mode==3 {bt_check(!bt_actor_result && !bt_peer_result && !esp_bt_rx,103);}
        if bt_mode==4 {bt_check(!bt_actor_result && !bt_peer_result && !esp_bt_rx,104);}
        if bt_mode==5 || bt_mode==6 {bt_check(!bt_actor_result && !bt_peer_result && bt_get(1)==1 && !bt_get(16),100+bt_mode);}
        if bt_mode==7 {bt_check(bt_actor_result==0x22 && bt_peer_result==0x55,107);}
        if bt_mode==8 {bt_check(bt_actor_result==0x22 && !bt_peer_result && bt_get(1)==1,108);}
        bt_check(!bt_get(2) && !esp_bt_tx_active && !esp_bt_cmd_busy && !esp_bt_cmd_pending,120);if bt_expect_hooks && (bt_mode<=4 || bt_mode==7) {bt_check(!bt_armed,121);}
        if bt_error {return bt_error;}esp_bt_vendor_initialized=0;if esp_bt_transport_release() {return 5;}bt_check(esp_sdk_heap_free()==baseline,122);if bt_error {return bt_error;}bt_mode=bt_mode+1;
    }
    // A submitted timeout quarantines the opcode; a late reply is asynchronous.
    bt_mode=10;bt_reset();if esp_bt_transport_init() {return 6;}bt_set(6,1);bt_check(esp_bt_hci_command(0x1001,0,0)== -110 && !esp_bt_cmd_busy && esp_bt_cmd_pending && esp_bt_cmd_stale,210);if bt_error {return bt_error;}let sent=bt_get(1);
    bt_check(esp_bt_hci_command(0x1001,0,0)== -16 && bt_get(1)==sent && esp_bt_transport_release()== -16,211);if bt_error {return bt_error;}bt_emit(0x1001,0x11,1);bt_check(!esp_bt_cmd_pending && !esp_bt_cmd_stale && !esp_bt_cmd_size && esp_bt_event_count==1,212);if bt_error {return bt_error;}
    bt_set(6,0);bt_set(7,0x22);bt_set(8,0x33);bt_set(9,0x1001);bt_check(esp_bt_hci_command(0x1001,0,0)==0x22 && bt_get(1)==sent+1,213);if bt_error {return bt_error;}
    bt_check(esp_bt_hci_next_event()==7 && load8(esp_bt_rx+6)==0x11 && esp_bt_hci_next_event()==7 && load8(esp_bt_rx+6)==0x33,214);if bt_error {return bt_error;}
    esp_bt_cmd_credits=3;bt_check(!esp_bt_hci_send_packet(bt_hnc,9) && esp_bt_cmd_credits==3 && esp_bt_hci_command(0x0c35,bt_hnc+4,5)== -22,215);if bt_error {return bt_error;}bt_emit(0x0c35,0x12,0);bt_check(esp_bt_cmd_credits==3 && esp_bt_hci_next_event()==7,216);if bt_error {return bt_error;}
    store8(bt_wire,4);store8(bt_wire+1,15);store8(bt_wire+2,4);store8(bt_wire+3,0x12);store8(bt_wire+4,0);store8(bt_wire+5,0x35);store8(bt_wire+6,0x0c);esp_bt_recv(bt_wire,7,0,0,0,0,0,0);bt_check(esp_bt_cmd_credits==3 && esp_bt_hci_next_event()==7,217);if bt_error {return bt_error;}
    // A second timeout can recover by stopping the controller without a reply.
    bt_set(6,1);bt_check(esp_bt_hci_command(0x1002,0,0)== -110 && esp_bt_cmd_pending,218);esp_bt_vendor_initialized=1;bt_check(!esp_bt_controller_deinit() && bt_get(16)==1 && !esp_bt_cmd_pending && !esp_bt_rx && esp_sdk_heap_free()==baseline,219);if bt_error {return bt_error;}
    bt_mode=9;bt_reset();if esp_bt_transport_init() {return 7;}let checks=bt_get(10);let ps=esp32_irq_save();bt_check(esp_bt_hci_send_packet(bt_packet,21)== -16 && esp_bt_hci_command(0x1001,0,0)== -16,220);esp32_irq_restore(ps);esp32_irq_raise(128);let begin=esp32_cycles();while !bt_phase && ((esp32_cycles()-begin)&4294967295)<1000000 {}bt_check(bt_phase && bt_get(10)==checks && !bt_get(2),221);if esp_bt_transport_release() {return 8;}
    let remaining=1000;while remaining<=11000 {let held=esp_sdk_malloc(baseline-remaining);if !held {return 9;}let free=esp_sdk_heap_free();bt_check(esp_bt_transport_init()== -12 && !esp_bt_rx && !esp_bt_cmd && !esp_bt_tx && esp_sdk_heap_free()==free,230);esp_sdk_free(held);if remaining==1000 {remaining=1500;}else if remaining==1500 {remaining=2200;}else if remaining==2200 {remaining=4000;}else if remaining==4000 {remaining=9000;}else {remaining=12000;}}
    bt_emit(0xffff,0,1);esp_bt_send_ready(0,0,0,0,0,0,0,0);bt_check(!esp_bt_tx_ready && !esp_bt_event_dropped && !esp_bt_acl_dropped && esp_sdk_heap_free()==baseline,231);bt_check(!esp_sdk_preempt_stop(),232);if bt_error {return bt_error;}
    esp_uart_write("PASS: preemptive VHCI admission, active C buffer lease, command quarantine/credits and transport lifetime; checks=");esp_uart_hex(bt_checks);esp_uart_write(" hooks=");esp_uart_hex(bt_hooks);esp_uart_write(" masked=");esp_uart_hex(bt_masked);esp_uart_write("\r\n");return 0;
}
