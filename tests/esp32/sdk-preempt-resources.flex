// Actual Xtensa scheduling; optional source-copy probes are inserted only by
// lifecycle-preempt-reference.py at the publication points under test.
import "../../lib/platform/esp32-xip.flex";
import "../../lib/platform/esp32-sdk-preempt.flex";
import "../../lib/platform/esp32-radio-os.flex";
global lr_expect_hooks=0;
global lr_mode=0;
global lr_armed=0;
global lr_phase=0;
global lr_actor_done=0;
global lr_peer_done=0;
global lr_actor_result=0;
global lr_peer_result=0;
global lr_actor_task=0;
global lr_child_bad=0;
global lr_child_done=0;
global lr_handle=0;
global lr_allocation=0;
global lr_hooks=0;
global lr_masked=0;
global lr_checks=0;
global lr_error=0;
fn lr_check(ok,code) {lr_checks=lr_checks+1;if !ok && !lr_error {lr_error=code;esp_uart_write("LIFECYCLE FAIL ");esp_uart_hex(code);esp_uart_write(" mode=");esp_uart_hex(lr_mode);esp_uart_write(" actor=");esp_uart_hex(lr_actor_result);esp_uart_write(" peer=");esp_uart_hex(lr_peer_result);esp_uart_write("\r\n");}return ok;}
fn lr_soft(source) {esp_sdk_reschedule_request();return 0;}
fn lr_probe(point) {
    if point!=lr_mode || !lr_armed {return 0;}lr_armed=0;lr_phase=1;lr_hooks=lr_hooks+1;
    let ps=esp32_irq_save();if ps&15 {lr_masked=lr_masked+1;}esp32_irq_restore(ps);esp32_irq_raise(128);
    // An unprotected copy must let the peer intervene before publication.
    // Protected code must return immediately and deliver the IRQ on unmask.
    if !(ps&15) {let end=esp_sdk_now()+200000;while !lr_peer_done && esp_sdk_now()<end {}}
    return 0;
}
fn lr_nop(a,b,c,d,e,f,g,h) {return 0;}
fn lr_child(a,b,c,d,e,f,g,h) {
    if esp32_load32(lr_handle)!=esp_sdk_current || load64(esp_sdk_current+584)!=1 {lr_child_bad=1;}lr_child_done=1;return 0;
}
fn lr_actor(a,b,c,d,e,f,g,h) {
    if lr_mode==1 {lr_actor_result=esp_radio_resources_begin(1);}
    if lr_mode==2 {lr_actor_result=esp_sdk_timer_init();}
    if lr_mode==3 {lr_actor_result=esp_sdk_timer_deinit();}
    if lr_mode==4 {lr_actor_result=esp_radio_resources_end(esp32_callback(lr_soft));}
    if lr_mode==5 {lr_actor_result=esp_radio_cb_task_create_any(esp32_callback32(lr_child),0,8192,0,7,lr_handle,0,0);}
    if lr_mode==6 {lr_actor_result=esp_radio_cb_task_create(esp32_callback32(lr_child),0,8192,0,7,lr_handle,0,0);}
    if lr_mode==7 {lr_actor_result=esp_radio_cb_malloc(37,0,0,0,0,0,0,0);lr_allocation=lr_actor_result;}
    if lr_mode==8 {lr_actor_result=esp_radio_cb_thread_sem(0,0,0,0,0,0,0,0);}
    lr_actor_done=1;return 0;
}
fn lr_peer(a,b,c,d,e,f,g,h) {
    while !lr_phase && !lr_actor_done {}
    if lr_mode==1 || lr_mode==4 {lr_peer_result=esp_radio_resources_begin(2);}
    if lr_mode==2 || lr_mode==3 {lr_peer_result=esp_sdk_timer_init();}
    if lr_mode==7 {lr_peer_result=esp_sdk_heap_owner(lr_allocation);}
    if lr_mode==8 {let s=load64(lr_actor_task+568);lr_peer_result=s && esp_sdk_heap_owner(s)==1;}
    lr_peer_done=1;return 0;
}
fn lr_join(t) {while load64(t+544)!=2 {esp_sdk_yield();}return 0;}
fn main() {
    if esp_sdk_heap_init(0x3ffc8000,98304) || esp_sdk_task_init() {return 1;}esp_irq_enable();lr_handle=alloc(8);lr_probe(0);
    if esp_irq_software(esp32_callback(lr_soft)) || esp_sdk_preempt_start(5000) {return 2;}let before=esp_sdk_heap_free();let repeat=0;
    // Publish dependent peers before a higher-priority worker can starve main.
    while repeat<4 {lr_mode=1;while lr_mode<=8 {
        lr_actor_done=0;lr_peer_done=0;lr_phase=0;lr_armed=1;lr_actor_result= -99;lr_peer_result= -99;lr_child_bad=0;lr_child_done=0;lr_allocation=0;esp32_store32(lr_handle,0);
        if lr_mode==3 && esp_sdk_timer_init() {return 3;}if lr_mode>=4 && esp_radio_resources_begin(1) {return 4;}
        let setup_ps=esp32_irq_save();let peer=esp_sdk_task_create(esp32_callback32(lr_peer),0,8192,5);lr_actor_task=esp_sdk_task_create(esp32_callback32(lr_actor),0,8192,5);esp32_irq_restore(setup_ps);if !peer || !lr_actor_task {return 5;}
        lr_join(lr_actor_task);lr_join(peer);
        if lr_mode==1 {lr_check(!lr_actor_result && lr_peer_result== -16 && esp_radio_owner==1,101);}
        if lr_mode==2 {lr_check(!lr_actor_result && lr_peer_result== -16 && esp_sdk_timer_task,102);}
        if lr_mode==3 {lr_check(!lr_actor_result && !lr_peer_result && esp_sdk_timer_task,103);}
        if lr_mode==4 {lr_check(!lr_actor_result && !lr_peer_result && esp_radio_owner==2,104);}
        if lr_mode==5 || lr_mode==6 {lr_check(lr_actor_result==1 && lr_child_done && !lr_child_bad,100+lr_mode);}
        if lr_mode==7 {lr_check(lr_actor_result && lr_peer_result==1 && esp_sdk_heap_owner(lr_actor_result)==1,107);}
        if lr_mode==8 {lr_check(lr_actor_result && lr_peer_result==1 && load64(lr_actor_task+568)==lr_actor_result,108);}
        if lr_expect_hooks {lr_check(!lr_armed,109);}if lr_error {return lr_error;}
        if esp_sdk_task_reap(lr_actor_task) || esp_sdk_task_reap(peer) {return 6;}if esp_radio_owner && esp_radio_resources_end(esp32_callback(lr_soft)) {return 7;}if esp_sdk_timer_deinit() {return 8;}
        lr_check(esp_sdk_heap_free()==before && load64(esp_sdk_tasks+536)==esp_sdk_tasks && !esp_radio_owner && !esp_sdk_timers && !esp_sdk_timer_active,110);
        lr_check(!(esp32_irq_save()&15),111);esp_irq_enable();if lr_error {return lr_error;}lr_mode=lr_mode+1;
    }repeat=repeat+1;}
    if lr_expect_hooks {lr_check(lr_hooks==32 && lr_masked==32,112);}if esp_sdk_preempt_stop() || lr_error {return 9;}
    esp_uart_write("PASS: radio/timer lifecycle ownership, task/handle/tag publication,32 lifetimes; checks=");esp_uart_hex(lr_checks);esp_uart_write(" hooks=");esp_uart_hex(lr_hooks);esp_uart_write(" masked=");esp_uart_hex(lr_masked);esp_uart_write("\r\n");return 0;
}
