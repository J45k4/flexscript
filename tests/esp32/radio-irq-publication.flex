// Real CPU7 delivery observes published pairs. External Wi-Fi/BT RF status
// is not modeled: software observers exercise their memory publication only.
import "../../lib/platform/esp32-xip.flex";
import "../../lib/platform/esp32-bluetooth.flex";
global ai_expect_hooks=0;
global ai_mode=0;
global ai_armed=0;
global ai_hooks=0;
global ai_masked=0;
global ai_delivered=0;
global ai_route_bad=0;
global ai_source=30;
global ai_checks=0;
global ai_error=0;
global ai_record=0;
global ai_old_arg=0;
global ai_new_arg=0;
global ai_pending_old=0;
global ai_pending_new=0;
fn ai_check(ok,code) {ai_checks=ai_checks+1;if !ok && !ai_error {ai_error=code;esp_uart_write("IRQ PUBLICATION FAIL ");esp_uart_hex(code);esp_uart_write(" mode=");esp_uart_hex(ai_mode);esp_uart_write(" old/new/bad=");esp_uart_hex(esp32_load32(ai_record));esp_uart_hex(esp32_load32(ai_record+4));esp_uart_hex(esp32_load32(ai_record+8));esp_uart_write(" delivered=");esp_uart_hex(ai_delivered);esp_uart_write("\r\n");}return ok;}
fn ai_app(source) {return 0;}
fn ai_soft_old(source) {ai_pending_old=ai_pending_old+1;return 0;}
fn ai_soft_new(source) {ai_pending_new=ai_pending_new+1;return 0;}
fn ai_seen() {if ai_mode<=4 {return esp32_load32(ai_record)+esp32_load32(ai_record+4);}return ai_delivered;}
fn ai_observer(source) {
    ai_delivered=ai_delivered+1;let callback=esp_radio_isr;let arg=esp_radio_isr_arg;
    if ai_mode==2 {callback=esp_bt_irq5;arg=esp_bt_arg5;}if ai_mode==4 {callback=esp_bt_irq8;arg=esp_bt_arg8;}
    if ai_mode<=4 {if callback {esp32_call32(callback,arg,0,0,0,0,0,0,0);}}
    if ai_mode==5 || ai_mode==6 {esp32_irq_mask(esp32_irq_enabled()|4);}
    if ai_mode==7 && (!load64(esp_radio_irq_routes+ai_source*16) || esp32_load32(0x3ff00104+ai_source*4)!=1) {ai_route_bad=1;}return 0;
}
fn ai_probe(point) {
    if point!=ai_mode || !ai_armed {return 0;}ai_armed=0;ai_hooks=ai_hooks+1;let ps=esp32_irq_save();if ps&15 {ai_masked=ai_masked+1;}esp32_irq_restore(ps);esp32_irq_raise(128);
    if !(ps&15) {let start=esp32_cycles();while !ai_seen() && ((esp32_cycles()-start)&4294967295)<1000000 {}}return 0;
}
fn ai_mask_probe(value,point) {ai_probe(point);return value;}
fn ai_reset_irq() {let ps=esp32_irq_save();esp32_irq_mask(0);esp32_irq_clear(128);esp_irq_soft_handler=0;esp_radio_isr=0;esp_radio_isr_arg=0;esp_bt_irq5=0;esp_bt_arg5=0;esp_bt_irq7=0;esp_bt_arg7=0;esp_bt_irq8=0;esp_bt_arg8=0;esp32_irq_restore(ps);return 0;}
fn ai_snapshot(buffer) {
    let at=buffer;let ps=esp32_irq_save();store64(at,esp_irq_count);store64(at+8,esp_irq_table);store64(at+16,esp_irq_soft_handler);store64(at+24,esp32_irq_enabled());store64(at+32,esp32_load32(esp32_state()));at=at+40;
    let i=0;while i<32 {let source=0;let handler=0;if i<esp_irq_count {source=load64(esp_irq_table+i*16);handler=load64(esp_irq_table+i*16+8);}store64(at,source);store64(at+8,handler);at=at+16;i=i+1;}
    i=0;while i<69 {store64(at,load64(esp_radio_irq_routes+i*16));store64(at+8,load64(esp_radio_irq_routes+i*16+8));store64(at+16,esp32_load32(0x3ff00104+i*4));at=at+24;i=i+1;}
    store64(at,esp_radio_isr);store64(at+8,esp_radio_isr_arg);store64(at+16,esp_bt_irq5);store64(at+24,esp_bt_arg5);store64(at+32,esp_bt_irq7);store64(at+40,esp_bt_arg7);store64(at+48,esp_bt_irq8);store64(at+56,esp_bt_arg8);store64(at+64,esp_radio_soft_owned);esp32_irq_restore(ps);return at+72-buffer;
}
fn ai_equal(a,b,n) {let i=0;while i<n {if load8(a+i)!=load8(b+i) {return 0;}i=i+1;}return 1;}
fn ai_remove_apps() {let s=0;while s<69 {if esp_irq_handler(s)==esp32_callback(ai_app) {esp_irq_detach(s);}s=s+1;}return 0;}
fn main() {
    if esp_sdk_heap_init(0x3ffc8000,98304) || esp_sdk_task_init() {return 1;}esp_irq_enable();ai_record=esp32_external("c_irq_publication");ai_old_arg=alloc(16);ai_new_arg=alloc(16);let before=alloc(4096);let after=alloc(4096);
    esp32_store32(ai_old_arg,0x4f4c4421);esp32_store32(ai_new_arg,0x4e455721);esp32_store32(ai_old_arg+4,0x13572468);esp32_store32(ai_new_arg+4,0x13572468);esp32_store32(ai_old_arg+8,0x24681357);esp32_store32(ai_new_arg+8,0x24681357);ai_probe(0);ai_mask_probe(0,0);
    let baseline=esp_sdk_heap_free();let old=esp32_external("c_irq_old");let new=esp32_external("c_irq_new");let repeat=0;
    while repeat<4 {ai_mode=1;while ai_mode<=7 {
        ai_reset_irq();let ps=esp32_irq_save();ai_armed=0;ai_delivered=0;ai_route_bad=0;let i=0;while i<4 {esp32_store32(ai_record+i*4,0);i=i+1;}
        if ai_mode!=3 && esp_irq_software(esp32_iram_callback(ai_observer)) {return 2;}let owner=2;if ai_mode==1 || ai_mode==5 || ai_mode==7 {owner=1;}if esp_radio_resources_begin(owner) {return 3;}
        if (ai_mode==1 || ai_mode==5) && esp_radio_cb_set_isr(0,old,ai_old_arg,0,0,0,0,0) {return 4;}
        if ai_mode==2 && esp_bt_set_isr(5,old,ai_old_arg,0,0,0,0,0) {return 5;}if ai_mode==3 && esp_bt_set_isr(7,old,ai_old_arg,0,0,0,0,0) {return 6;}
        if (ai_mode==4 || ai_mode==6) && esp_bt_set_isr(8,old,ai_old_arg,0,0,0,0,0) {return 7;}
        if ai_mode==7 {esp32_store32(0x3ff00104+ai_source*4,6);}ai_armed=1;esp32_irq_restore(ps);let result=0;
        if ai_mode==1 {result=esp_radio_cb_set_isr(0,new,ai_new_arg,0,0,0,0,0);}if ai_mode==2 {result=esp_bt_set_isr(5,new,ai_new_arg,0,0,0,0,0);}if ai_mode==3 {result=esp_bt_set_isr(7,new,ai_new_arg,0,0,0,0,0);}if ai_mode==4 {result=esp_bt_set_isr(8,new,ai_new_arg,0,0,0,0,0);}
        if ai_mode==5 {result=esp_radio_cb_ints_on(0,0,0,0,0,0,0,0);}if ai_mode==6 {result=esp_bt_ints_on(0,0,0,0,0,0,0,0);}if ai_mode==7 {result=esp_radio_cb_set_intr(0,ai_source,1,1,0,0,0,0);}
        if ai_armed && !ai_expect_hooks {ai_armed=0;esp32_irq_raise(128);}let start=esp32_cycles();while !ai_seen() && ((esp32_cycles()-start)&4294967295)<1000000 {}
        let ok=!result && !ai_armed;if ai_mode<=4 {ok=ok && !esp32_load32(ai_record) && esp32_load32(ai_record+4)==1 && !esp32_load32(ai_record+8);}if ai_mode==5 || ai_mode==6 {ok=ok && ai_delivered==1 && (esp32_irq_enabled()&4);}if ai_mode==7 {ok=ok && ai_delivered==1 && !ai_route_bad;}ai_check(ok,100+ai_mode);
        ps=esp32_irq_save();ai_check(!(ps&15),120);let handler=esp32_iram_callback(esp_bt_irq);if owner==1 {handler=esp32_callback(esp_radio_irq);}ai_check(!esp_radio_resources_end(handler) && !esp_radio_owner && !esp_irq_count && esp_sdk_heap_free()==baseline,121);esp32_irq_restore(ps);if ai_error {return ai_error;}ai_mode=ai_mode+1;
    }repeat=repeat+1;}
    if ai_expect_hooks {ai_check(ai_hooks==28 && ai_masked==28,122);}ai_reset_irq();
    // Native handler replacement must retain an existing pending event, while
    // initial installation intentionally drops stale unowned software state.
    let ps=esp32_irq_save();esp32_irq_raise(128);esp_irq_software(esp32_callback(ai_soft_old));esp32_irq_restore(ps);ai_check(!ai_pending_old && !esp32_irq_pending(),130);
    ps=esp32_irq_save();esp32_irq_raise(128);esp_irq_software(esp32_callback(ai_soft_new));esp32_irq_restore(ps);ai_check(!ai_pending_old && ai_pending_new==1 && !(esp32_irq_pending()&128),131);ai_reset_irq();
    // Full table failures preserve bindings, claims, every route and enables.
    ai_mode=0;let n=0;let s=1;while n<32 {if esp_irq_attach(s,esp32_callback(ai_app)) {return 8;}n=n+1;s=s+1;}if esp_radio_resources_begin(1) {return 9;}let size=ai_snapshot(before);let result=esp_radio_cb_set_isr(0,new,ai_new_arg,0,0,0,0,0);ai_snapshot(after);ai_check(result== -12 && ai_equal(before,after,size),201);ai_remove_apps();esp_radio_resources_end(esp32_callback(esp_radio_irq));ai_reset_irq();
    n=0;s=0;while n<31 {if s!=6 && s!=7 {if esp_irq_attach(s,esp32_callback(ai_app)) {return 10;}n=n+1;}s=s+1;}if esp_radio_resources_begin(2) {return 11;}size=ai_snapshot(before);result=esp_bt_set_isr(5,new,ai_new_arg,0,0,0,0,0);ai_snapshot(after);ai_check(result== -12 && ai_equal(before,after,size),202);ai_remove_apps();esp_radio_resources_end(esp32_iram_callback(esp_bt_irq));ai_reset_irq();
    if esp_irq_attach(7,esp32_callback(ai_app)) || esp_radio_resources_begin(2) {return 12;}size=ai_snapshot(before);result=esp_bt_set_isr(5,new,ai_new_arg,0,0,0,0,0);ai_snapshot(after);ai_check(result== -16 && ai_equal(before,after,size),203);ai_remove_apps();esp_radio_resources_end(esp32_iram_callback(esp_bt_irq));ai_reset_irq();
    if esp_radio_resources_begin(2) || esp_radio_irq_claim(4) || esp_irq_attach(4,esp32_callback(ai_app)) {return 13;}size=ai_snapshot(before);result=esp_bt_set_isr(8,new,ai_new_arg,0,0,0,0,0);ai_snapshot(after);ai_check(result== -16 && ai_equal(before,after,size),204);ai_remove_apps();esp_radio_resources_end(esp32_iram_callback(esp_bt_irq));ai_reset_irq();
    if esp_radio_resources_begin(2) || esp_irq_software(esp32_callback(ai_app)) {return 14;}size=ai_snapshot(before);result=esp_bt_set_isr(7,new,ai_new_arg,0,0,0,0,0);ai_snapshot(after);ai_check(result== -16 && ai_equal(before,after,size),205);esp_radio_resources_end(esp32_iram_callback(esp_bt_irq));ai_reset_irq();
    ai_check(esp_bt_set_isr(7,new,ai_new_arg,0,0,0,0,0)== -22 && !esp_irq_soft_handler && !esp32_irq_enabled(),206);ai_check(esp_irq_reserve(-1)== -22 && esp_irq_reserve(33)== -22 && !esp_irq_reserve(0),207);
    ai_check(esp_sdk_heap_free()==baseline && !esp_irq_count && !esp_radio_owner && !esp32_load32(esp32_state()+16),208);if ai_error {return ai_error;}
    esp_uart_write("PASS: IRQ callback pairs, pending replacement, atomic enables and transaction failures; checks=");esp_uart_hex(ai_checks);esp_uart_write(" hooks=");esp_uart_hex(ai_hooks);esp_uart_write(" masked=");esp_uart_hex(ai_masked);esp_uart_write("\r\n");return 0;
}
