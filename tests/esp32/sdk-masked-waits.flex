import "../../lib/platform/esp32-xip.flex";
import "../../lib/platform/esp32-sdk-preempt.flex";
import "../../lib/platform/esp32-wifi.flex";
import "../../lib/platform/esp32-bluetooth.flex";
global mw_ref=0;
global mw_sem=0;
global mw_gate=0;
global mw_empty=0;
global mw_full=0;
global mw_mutex=0;
global mw_recursive=0;
global mw_event=0;
global mw_word=0;
global mw_out=0;
global mw_owner=0;
global mw_owner_ready=0;
global mw_peer_ran=0;
global mw_timer_calls=0;
global mw_clock_calls=0;
global mw_clock_before=0;
global mw_snapshot=0;
global mw_checks=0;
global mw_error=0;
global mw_in_irq=0;
global mw_irq_done=0;
global mw_hook_calls=0;
fn mw_check(ok,code) {mw_checks=mw_checks+1;if !ok && !mw_error {mw_error=code;esp_uart_write("MASKED WAIT FAIL ");esp_uart_hex(code);esp_uart_write(" peer/Cbad/vendor=");esp_uart_hex(mw_peer_ran);esp_uart_hex(esp32_load32(mw_ref+4));esp_uart_hex(esp32_load32(mw_ref+8));esp_uart_write("\r\n");}return ok;}
fn mw_action(action) {
    if action==1 {return esp_sdk_yield();}if action==2 {return esp_sdk_delay(0);}if action==3 {return esp_sdk_delay(2);}
    if action==4 {return esp_sdk_task_wait(1,mw_sem,0,0,1);}if action==5 {return esp_sdk_task_delete(0);}
    if action==6 {return esp_sdk_sem_take(mw_sem,2);}if action==7 {return esp_sdk_sem_take(mw_sem,4294967295);}
    if action==8 {return esp_sdk_queue_op(mw_empty,mw_out,2,0);}if action==9 {return esp_sdk_queue_op(mw_full,mw_word,2,1);}
    if action==10 {return esp_sdk_mutex_lock(mw_mutex);}if action==11 {return esp_sdk_event_wait(mw_event,1,1,1,2);}
    if action==12 {return esp_wifi_station_stop();}if action==13 {let before=esp_wifi_vendor_running;esp_wifi_vendor_running=0;let r=esp_wifi_station_start();esp_wifi_vendor_running=before;return r;}
    if action==14 {return esp_wifi_station_deinit();}if action==15 {let before=esp_wifi_initialized;esp_wifi_initialized=0;let r=esp_wifi_station_init();esp_wifi_initialized=before;return r;}
    if action==16 {return esp_bt_controller_init();}if action==17 {return esp_bt_controller_deinit();}if action==18 {return esp_sdk_timer_poll();}return -22;
}
fn mw_expected(action) {if action>=6 && action<=10 {return 0;}if action==11 {return 2;}return -16;}
fn mw_callback(a,b,c,d,e,f,g,h) {return mw_action(a);}
fn mw_copy(from,to,n) {let i=0;while i<n {store8(to+i,load8(from+i));i=i+1;}return 0;}
fn mw_equal(a,b,n) {let i=0;while i<n {if load8(a+i)!=load8(b+i) {return 0;}i=i+1;}return 1;}
fn mw_snapshot_take() {
    mw_clock_before=mw_clock_calls;mw_copy(esp_sdk_current,mw_snapshot,640);mw_copy(mw_sem,mw_snapshot+640,32);mw_copy(mw_empty,mw_snapshot+672,48);mw_copy(mw_full,mw_snapshot+720,48);mw_copy(mw_mutex,mw_snapshot+768,32);mw_copy(mw_event,mw_snapshot+800,16);return 0;
}
fn mw_snapshot_same() {return mw_equal(esp_sdk_current,mw_snapshot,640) && mw_equal(mw_sem,mw_snapshot+640,32) && mw_equal(mw_empty,mw_snapshot+672,48) && mw_equal(mw_full,mw_snapshot+720,48) && mw_equal(mw_mutex,mw_snapshot+768,32) && mw_equal(mw_event,mw_snapshot+800,16) && mw_clock_before==mw_clock_calls && !mw_peer_ran && !mw_timer_calls && !esp32_load32(mw_ref+8);}
fn mw_owner_task(a,b,c,d,e,f,g,h) {if !esp_sdk_mutex_lock(mw_mutex) {return 1;}mw_owner_ready=1;esp_sdk_sem_take(mw_gate,1000);esp_sdk_mutex_unlock(mw_mutex);return 0;}
fn mw_peer(a,b,c,d,e,f,g,h) {mw_peer_ran=mw_peer_ran+1;return 0;}
fn mw_timer(a,b,c,d,e,f,g,h) {mw_timer_calls=mw_timer_calls+1;return 0;}
fn mw_wake(a,b,c,d,e,f,g,h) {esp_sdk_delay(2);esp_sdk_sem_give(mw_sem);esp_sdk_queue_try(mw_empty,mw_word,1);esp_sdk_event_set(mw_event,1);return 0;}
fn mw_join(t) {while load64(t+544)!=2 {esp_sdk_yield();}return esp_sdk_task_reap(t);}
fn mw_rejections() {
    let action=1;while action<=18 {
        mw_snapshot_take();let r=mw_action(action);mw_check(r==mw_expected(action) && mw_snapshot_same(),100+action);if mw_error {return mw_error;}action=action+1;
    }return 0;
}
fn mw_irq(source) {mw_in_irq=1;mw_rejections();mw_in_irq=0;mw_irq_done=1;return 0;}
fn mw_hook(id) {mw_hook_calls=mw_hook_calls+1;let data=esp_radio_event_data;let size=esp_radio_event_size;mw_rejections();mw_check(esp_radio_event_data==data && esp_radio_event_size==size,220);return 0;}
fn main() {
    if esp_sdk_heap_init(0x3ffc8000,98304) || esp_sdk_task_init() {return 1;}esp_irq_enable();mw_ref=esp32_external("masked_wait_peer");mw_sem=esp_sdk_sem_create(1,0);mw_gate=esp_sdk_sem_create(1,0);mw_empty=esp_sdk_queue_create(1,8);mw_full=esp_sdk_queue_create(1,8);mw_mutex=esp_sdk_mutex_create(0);mw_recursive=esp_sdk_mutex_create(1);mw_event=esp_sdk_event_create();mw_word=alloc(8);mw_out=alloc(8);mw_snapshot=alloc(832);store64(mw_word,0x123456789abcdef0);store64(mw_out,0x13572468);esp_sdk_queue_try(mw_full,mw_word,1);esp_sdk_event_set(mw_event,2);
    mw_owner=esp_sdk_task_create(esp32_callback32(mw_owner_task),0,8192,5);if !mw_owner {return 2;}while !mw_owner_ready {esp_sdk_yield();}
    if esp_irq_software(esp32_callback(mw_irq)) || esp_sdk_preempt_start(5000) {return 3;}
    esp_wifi_initialized=1;esp_wifi_vendor_initialized=1;esp_wifi_vendor_running=1;esp_wifi_supplicant=1;esp_wifi_started=1;
    // Sentinels make any rejected wait publication/reset visible in the TCB.
    store64(esp_sdk_current+600,0x11111111);store64(esp_sdk_current+608,0x22222222);store64(esp_sdk_current+616,0x33333333);
    let saved=esp32_irq_save();let peer=esp_sdk_task_create(esp32_callback32(mw_peer),0,8192,5);if !peer {return 4;}
    let action=1;while action<=18 {
        mw_snapshot_take();let r=esp32_call32(esp32_external("masked_wait_probe"),esp32_callback32(mw_callback),action,mw_expected(action)&4294967295,0,0,0,0,0);
        mw_check(!r && mw_snapshot_same(),100+action);if mw_error {return mw_error;}action=action+1;
    }
    mw_check(esp32_load32(mw_ref)==54,201);
    // Immediate masked operations still work, including recursive ownership.
    mw_check(esp_sdk_sem_give(mw_sem) && esp_sdk_sem_take(mw_sem,100),202);
    mw_check(esp_sdk_queue_op(mw_full,mw_out,100,0) && load64(mw_out)==load64(mw_word) && esp_sdk_queue_op(mw_full,mw_word,100,1),203);
    mw_check(esp_sdk_mutex_lock(mw_recursive) && esp_sdk_mutex_lock(mw_recursive) && load64(mw_recursive+8)==2 && esp_sdk_mutex_unlock(mw_recursive) && esp_sdk_mutex_unlock(mw_recursive),204);
    esp_sdk_event_set(mw_event,1);mw_check(esp_sdk_event_wait(mw_event,1,1,1,100)==3 && load64(mw_event)==2,205);mw_check(!mw_peer_ran,206);esp32_irq_restore(saved);mw_join(peer);mw_check(mw_peer_ran==1,207);mw_peer_ran=0;
    // IRQ and bounded event-hook calls exercise the same rejection contract.
    store64(esp_sdk_current+600,0);store64(esp_sdk_current+608,0);store64(esp_sdk_current+616,0);
    esp32_irq_raise(128);let start=esp32_cycles();while !mw_irq_done && ((esp32_cycles()-start)&4294967295)<1000000 {}mw_check(mw_irq_done,208);if mw_error {return mw_error;}
    esp_radio_event_hook=esp32_callback(mw_hook);mw_check(!esp_radio_dispatch_event(99,mw_word,8) && mw_hook_calls==1 && !esp_radio_event_data && !esp_radio_event_size,209);esp_radio_event_hook=0;if mw_error {return mw_error;}
    // A due timer cannot consume its deadline or invoke C while masked.
    let key=alloc(8);if esp_sdk_timer_setfn(key,esp32_callback32(mw_timer),0) || esp_sdk_timer_arm(key,0,0) {return 5;}let node=esp_sdk_timer_find(key);let before=alloc(48);mw_copy(node,before,48);saved=esp32_irq_save();mw_check(esp_sdk_timer_poll()== -16 && mw_equal(node,before,48) && !mw_timer_calls,210);esp32_irq_restore(saved);while !mw_timer_calls {esp_sdk_timer_poll();}mw_check(mw_timer_calls==1,211);esp_sdk_timer_done(key);
    // Ordinary unmasked waits still block and wake through the real scheduler.
    let worker=esp_sdk_task_create(esp32_callback32(mw_wake),0,8192,5);if !worker {return 6;}mw_check(esp_sdk_sem_take(mw_sem,100) && esp_sdk_queue_op(mw_empty,mw_out,100,0) && load64(mw_out)==load64(mw_word) && esp_sdk_event_wait(mw_event,1,1,1,100)==3,212);mw_join(worker);
    esp_sdk_sem_give(mw_gate);mw_join(mw_owner);mw_check(esp_sdk_mutex_lock(mw_mutex) && esp_sdk_mutex_unlock(mw_mutex),213);mw_check(!esp_sdk_preempt_stop(),214);if mw_error {return mw_error;}
    esp_uart_write("PASS: masked/ISR switch and wait rejection, exact TCB/object/PS preservation, immediate tries and ordinary wakes; checks=");esp_uart_hex(mw_checks);esp_uart_write(" C cases=");esp_uart_hex(esp32_load32(mw_ref));esp_uart_write("\r\n");return 0;
}
