import "../../lib/platform/esp32-xip.flex";
import "../../lib/platform/esp32-sdk-preempt.flex";
import "../../lib/platform/esp32-radio-os.flex";
global ev_expect_hooks=0;
global ev_ref=0;
global ev_log=0;
global ev_mode=0;
global ev_phase=0;
global ev_armed=0;
global ev_done=0;
global ev_peer_done=0;
global ev_hooks=0;
global ev_masked=0;
global ev_deliveries=0;
global ev_callback_count=0;
global ev_actor_result=0;
global ev_peer_result=0;
global ev_checks=0;
global ev_error=0;
fn ev_get(i) {return esp32_load32(ev_ref+i*4);}
fn ev_set(i,v) {esp32_store32(ev_ref+i*4,v);return 0;}
fn ev_check(ok,code) {ev_checks=ev_checks+1;if !ok && !ev_error {ev_error=code;esp_uart_write("RADIO EVENT FAIL ");esp_uart_hex(code);esp_uart_write(" mode/bad/count=");esp_uart_hex(ev_mode);esp_uart_hex(ev_get(2));esp_uart_hex(esp_radio_events);esp_uart_write("\r\n");}return ok;}
fn ev_emit(adapter,id,marker,size,null_data) {return esp32_call32(esp32_external("radio_event_emit"),adapter,id,marker,size,null_data,0,0,0);}
fn ev_observe(id) {return esp32_call32(esp32_external("radio_event_observe"),id,esp_radio_event_data,esp_radio_event_size,0,0,0,0,0);}
fn ev_soft(source) {ev_deliveries=ev_deliveries+1;esp_sdk_reschedule_request();return 0;}
fn ev_gate(point) {
    if !ev_armed || point!=ev_mode {return 0;}ev_armed=0;ev_hooks=ev_hooks+1;ev_phase=point;let ps=esp32_irq_save();if ps&15 {ev_masked=ev_masked+1;}esp32_irq_restore(ps);esp32_irq_raise(128);
    if !(ps&15) {let begin=esp32_cycles();while !ev_peer_done && ((esp32_cycles()-begin)&4294967295)<8000000 {}}return 0;
}
fn ev_hook(id) {
    ev_callback_count=ev_callback_count+1;ev_observe(id);
    if ev_mode==4 && id==300 {
        let data=esp_radio_event_data;let size=esp_radio_event_size;
        ev_check(!ev_emit(1,301,301,8,0) && esp_radio_event_data==data && esp_radio_event_size==size,401);
        let hook=esp_radio_event_hook;esp_radio_event_hook=0;
        ev_check(!ev_emit(0,302,302,8,0) && esp_radio_event_data==data && esp_radio_event_size==size,402);esp_radio_event_hook=hook;ev_observe(id);
    }return 0;
}
fn ev_reset() {
    let i=0;while i<32 {ev_set(i,0);i=i+1;}ev_set(0,esp32_callback32(esp_event_post));ev_set(1,esp32_callback32(esp_radio_cb_event_post));esp_radio_event_hook=esp32_callback(ev_hook);
    esp_radio_events=0;esp_radio_last_event=0;esp_radio_scan_status= -1;esp_radio_scan_done=0;esp_radio_event_data=0;esp_radio_event_size=0;ev_callback_count=0;ev_phase=0;ev_armed=0;ev_done=0;ev_peer_done=0;ev_actor_result= -99;ev_peer_result= -99;return 0;
}
fn ev_actor(a,b,c,d,e,f,g,h) {let id=101;let marker=101;if ev_mode==2 {id=1;marker=17;}ev_actor_result=ev_emit(0,id,marker,8,0);ev_done=1;return 0;}
fn ev_peer(a,b,c,d,e,f,g,h) {
    while !ev_phase && !ev_done {}
    let id=101;if ev_mode==2 {id=1;}
    let ok=esp_radio_events==1 && esp_radio_last_event==id && !esp_radio_event_data && !esp_radio_event_size && ev_callback_count==1;
    if ev_mode==2 {ok=ok && esp_radio_scan_done && esp_radio_scan_status==17;}
    ev_peer_result=0;if !ok {ev_peer_result= -5;}ev_emit(1,202,202,8,0);ev_peer_done=1;return 0;
}
fn ev_join(t) {while load64(t+544)!=2 {esp_sdk_yield();}return esp_sdk_task_reap(t);}
fn ev_log_is(slot,id,marker,size) {return esp32_load32(ev_log+slot*16)==id && esp32_load32(ev_log+slot*16+4)==marker && esp32_load32(ev_log+slot*16+8)==size && esp32_load32(ev_log+slot*16+12)==15;}
fn main() {
    if esp_sdk_heap_init(0x3ffc8000,98304) || esp_sdk_task_init() {return 1;}esp_irq_enable();ev_ref=esp32_external("radio_event_peer");ev_log=esp32_external("radio_event_log");ev_gate(0);
    if esp_irq_software(esp32_callback(ev_soft)) || esp_sdk_preempt_start(5000) {return 2;}let baseline=esp_sdk_heap_free();ev_mode=1;
    while ev_mode<=3 {
        esp_uart_write("EVENT CASE ");esp_uart_hex(ev_mode);esp_uart_write("\r\n");ev_reset();ev_armed=1;
        let ps=esp32_irq_save();let peer=esp_sdk_task_create(esp32_callback32(ev_peer),0,8192,5);let actor=esp_sdk_task_create(esp32_callback32(ev_actor),0,8192,5);esp32_irq_restore(ps);if !peer || !actor {return 3;}ev_join(actor);ev_join(peer);
        let id=101;let marker=101;if ev_mode==2 {id=1;marker=17;}
        ev_check(!ev_actor_result && !ev_peer_result && !ev_get(2) && esp_radio_events==2 && esp_radio_last_event==202 && ev_callback_count==2 && ev_get(3)==2 && ev_get(4)==2 && ev_log_is(0,id,marker,8) && ev_log_is(1,202,202,8) && !esp_radio_event_data && !esp_radio_event_size,100+ev_mode);
        if ev_expect_hooks {ev_check(!ev_armed,200+ev_mode);}ev_check(esp_sdk_heap_free()==baseline,300+ev_mode);if ev_error {return ev_error;}ev_mode=ev_mode+1;
    }
    // A nested post restores the suspended outer payload. Last-event and count
    // retain the newest publication rather than rewinding with hook context.
    ev_mode=4;ev_reset();ev_check(!ev_emit(0,300,300,8,0) && !ev_get(2) && esp_radio_events==3 && esp_radio_last_event==302 && ev_callback_count==2 && ev_get(3)==3 && ev_get(4)==3 && ev_log_is(0,300,300,8) && ev_log_is(1,301,301,8) && ev_log_is(2,300,300,8) && !esp_radio_event_data && !esp_radio_event_size,403);if ev_error {return ev_error;}
    // Caller PS and a borrowed outer view survive both hook and no-hook paths.
    ev_mode=5;ev_reset();let sentinel=alloc(8);let level=0;
    while level<=15 {
        let saved=esp32_irq_save();let masked=(saved&~15)|level;esp32_irq_restore(masked);esp_radio_event_data=sentinel;esp_radio_event_size=77;
        ev_check(!ev_emit(level&1,400+level,400+level,8,0),410);let actual=esp32_irq_save();ev_check((actual&15)==level && esp_radio_event_data==sentinel && esp_radio_event_size==77,411);esp32_irq_restore(actual);
        let hook=esp_radio_event_hook;esp_radio_event_hook=0;ev_check(!ev_emit(0,500+level,500+level,8,0) && esp_radio_event_data==sentinel && esp_radio_event_size==77,412);actual=esp32_irq_save();ev_check((actual&15)==level,413);esp_radio_event_hook=hook;esp_radio_event_data=0;esp_radio_event_size=0;esp32_irq_restore(saved);
        if level==0 {level=3;}else if level==3 {level=15;}else {level=16;}
    }
    ev_check(esp_radio_events==6 && ev_callback_count==3 && !ev_get(2),414);if ev_error {return ev_error;}
    ev_mode=6;ev_reset();let size=0;while size<=8 {let null=0;while null<2 {let marker=31+size;ev_check(!ev_emit(size&1,1,marker,size,null) && esp_radio_scan_done && esp_radio_last_event==1,420);let expected= -1;if !null && size>=6 {expected=marker;}ev_check(esp_radio_scan_status==expected && !esp_radio_event_data && !esp_radio_event_size,421);null=null+1;}size=size+1;}
    ev_check(esp_radio_events==18 && ev_callback_count==18 && !ev_get(2) && esp_sdk_heap_free()==baseline,422);
    esp_radio_event_hook=0;ev_check(!ev_emit(1,99,99,8,0) && esp_radio_events==19 && esp_radio_last_event==99 && esp_radio_scan_done && esp_radio_scan_status== -1,423);
    if ev_expect_hooks {ev_check(ev_hooks==3 && ev_masked==3,424);}ev_check(!esp_sdk_preempt_stop(),425);if ev_error {return ev_error;}
    esp_uart_write("PASS: radio event count/scan publication, nested hook payloads and saved PS; checks=");esp_uart_hex(ev_checks);esp_uart_write(" hooks=");esp_uart_hex(ev_hooks);esp_uart_write(" masked=");esp_uart_hex(ev_masked);esp_uart_write("\r\n");return 0;
}
