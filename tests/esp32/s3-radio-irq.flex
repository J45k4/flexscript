import "../../lib/platform/esp32s3-xip.flex";
import "../../lib/platform/esp32s3-radio-irq.flex";
global si_checks=0;
global si_soft_runs=0;
global si_pending=0;
global si_forced=0;
global si_old_arg=0;
global si_new_arg=0;
fn si_expect(ok) {si_checks=si_checks+1;if !ok {esp_uart_write("S3 IRQ check failed ");esp_uart_hex(si_checks);esp_uart_write("\r\n");}return ok;}
fn si_dummy(source) {return 0;}
fn si_soft(source) {si_soft_runs=si_soft_runs+1;esp_radio_irq(0);esp_radio_irq(2);return 0;}
// Only the isolated publication test inserts this probe and substitutes a
// scripted status read. The software interrupt itself executes on Xtensa.
fn si_status() {return si_pending;}
fn si_probe() {esp32_irq_raise(128);let start=esp32_cycles();while ((esp32_cycles()-start)&4294967295)<12000 {}return 0;}
fn si_trigger() {let ps=esp32_irq_save();let mask=esp32_irq_enabled();esp32_irq_mask(mask&~2);let wanted=si_soft_runs+1;esp32_irq_raise(128);esp32_irq_restore(0);let start=esp32_cycles();while si_soft_runs<wanted && ((esp32_cycles()-start)&4294967295)<1000000 {}esp32_irq_save();esp32_irq_mask(mask);esp32_irq_restore(ps);return si_soft_runs==wanted;}
fn si_call(function,a,b,c) {return esp32_call32(function,a,b,c,0,0,0,0,0);}
fn main() {
    let arena=esp_sdk_heap_min();if esp_sdk_heap_init(arena,esp_sdk_heap_max()-arena) || esp_sdk_task_init() {return 1;}
    let available=esp_sdk_heap_free();let old_fn=esp32_external("c_s3_irq_old");let new_fn=esp32_external("c_s3_irq_new");let counts=esp32_external("c_s3_irq_counts");let contract=esp32_external("c_s3_irq_contract");
    if !si_expect(si_call(contract,0,0,0)==0 && si_call(contract,1,0,0)==2 && si_call(contract,2,0,0)==esp_radio_route(0) && si_call(contract,3,0,0)==esp_radio_route(2) && si_call(contract,4,0,0)==0x600c218c) {return 2;}
    si_old_arg=alloc(12);si_new_arg=alloc(12);esp32_store32(si_old_arg,0x4f4c4421);esp32_store32(si_new_arg,0x4e455721);esp32_store32(si_old_arg+4,0x13572468);esp32_store32(si_new_arg+4,0x13572468);esp32_store32(si_old_arg+8,0x24681357);esp32_store32(si_new_arg+8,0x24681357);
    if !si_expect(esp_radio_cb_set_isr(0,old_fn,si_old_arg,0,0,0,0,0)== -22 && !esp_radio_isr && !esp_irq_count) {return 3;}
    if !si_expect(!esp_radio_resources_begin(2) && esp_radio_cb_set_isr(0,old_fn,si_old_arg,0,0,0,0,0)== -22 && esp_radio_cb_set_intr(0,0,1,1,0,0,0,0)== -22 && esp_radio_cb_ints_on(3,0,0,0,0,0,0,0)== -22 && esp_radio_s3_irq_deinit()== -22 && !esp_radio_isr && !esp_irq_count && !esp_radio_resources_end(esp32_callback(esp_radio_irq))) {return 24;}
    if !si_expect(!esp_radio_resources_begin(1)) {return 4;}
    let r0=esp32_load32(esp_radio_route(0));let r2=esp32_load32(esp_radio_route(2));esp32_store32(esp_radio_route(0),17);esp32_store32(esp_radio_route(2),18);
    let handler=esp32_callback(esp_radio_irq);let dummy=esp32_callback(si_dummy);
    esp_irq_attach(2,dummy);if !si_expect(esp_radio_cb_set_isr(0,old_fn,si_old_arg,0,0,0,0,0)== -16 && !esp_irq_handler(0) && esp_irq_handler(2)==dummy && !esp_radio_isr && !load64(esp_radio_irq_routes)) {return 5;}esp_irq_detach(2);esp32_store32(esp_radio_route(2),18);
    let i=3;while i<34 {if esp_irq_attach(i,dummy) {return 6;}i=i+1;}
    if !si_expect(esp_radio_cb_set_isr(0,old_fn,si_old_arg,0,0,0,0,0)== -12 && esp_irq_count==31 && !esp_radio_isr && !load64(esp_radio_irq_routes) && !load64(esp_radio_irq_routes+32) && esp32_load32(esp_radio_route(0))==17 && esp32_load32(esp_radio_route(2))==18) {return 7;}
    esp_irq_detach(33);if !si_expect(!esp_radio_cb_set_intr(1,0,31,7,0,0,0,0) && esp32_load32(esp_radio_route(0))==6 && !esp_radio_isr) {return 8;}
    if !si_expect(!esp_radio_cb_set_isr(0,old_fn,si_old_arg,0,0,0,0,0) && esp_irq_count==32 && esp_irq_handler(0)==handler && esp_irq_handler(2)==handler && esp_radio_isr==old_fn && esp_radio_isr_arg==si_old_arg) {return 9;}
    if !si_expect(esp32_load32(esp_radio_route(0))==1 && esp32_load32(esp_radio_route(2))==1 && (esp32_irq_enabled()&2)) {return 10;}
    if !si_expect(esp_radio_cb_set_isr(-1,old_fn,si_old_arg,0,0,0,0,0)== -22 && esp_radio_cb_set_isr(2,old_fn,si_old_arg,0,0,0,0,0)== -22 && esp_radio_cb_set_isr(0,0,si_old_arg,0,0,0,0,0)== -22 && esp_radio_cb_set_isr(0,0x140000000,si_old_arg,0,0,0,0,0)== -22 && esp_radio_isr==old_fn && esp_radio_isr_arg==si_old_arg) {return 11;}
    if !si_expect(esp_radio_cb_set_intr(0,1,1,1,0,0,0,0)== -22 && esp_radio_cb_clear_intr(-1,0,0,0,0,0,0,0)== -22 && esp_radio_cb_clear_intr(99,0,0,0,0,0,0,0)== -22) {return 12;}
    let soft_before=esp_irq_soft_handler;let mask_before=esp32_irq_enabled();esp_irq_software(esp32_callback(si_soft));let mask=esp32_irq_enabled();
    si_pending=5;if !si_expect(!esp_radio_cb_ints_off(3,0,0,0,0,0,0,0) && esp32_irq_enabled()==mask && esp32_load32(esp_radio_route(0))==6 && esp32_load32(esp_radio_route(2))==6 && si_trigger() && !esp32_load32(counts) && !esp32_load32(counts+4)) {return 13;}
    if !si_expect(!esp_radio_cb_ints_on(3,0,0,0,0,0,0,0) && si_trigger()) {return 14;}
    let bits=esp32_load32(0x600c218c)&5;if si_forced {bits=5;}let first=(bits&1)+((bits>>2)&1);let mac=bits&1;if !si_expect(esp32_load32(counts)==first && !esp32_load32(counts+4) && !esp32_load32(counts+8) && esp_radio_irq_count==first) {esp_uart_hex(esp32_load32(0x600c218c));esp_uart_hex(esp32_load32(counts));esp_uart_hex(esp32_load32(counts+4));esp_uart_hex(esp32_load32(counts+8));esp_uart_hex(esp_radio_irq_count);return 15;}
    let original_ps=esp32_irq_save();let ps=esp32_irq_save();esp32_irq_mask(mask&~2);esp32_irq_raise(128);if !si_expect(!esp_radio_cb_set_isr(1,new_fn,si_new_arg,0,0,0,0,0) && esp32_irq_save()==ps) {return 16;}esp32_irq_mask(mask&~2);esp32_irq_restore(0);
    let start=esp32_cycles();while si_soft_runs<3 && ((esp32_cycles()-start)&4294967295)<1000000 {}esp32_irq_save();esp32_irq_mask(mask);esp32_irq_restore(original_ps);
    if !si_expect(esp32_load32(counts)==first && esp32_load32(counts+4)==first && !esp32_load32(counts+8) && esp_radio_irq_count==first*2) {return 17;}
    let extra=0;if si_forced {si_pending=1;if !si_expect(si_trigger() && esp32_load32(counts+4)==first+1) {return 25;}si_pending=4;if !si_expect(si_trigger() && esp32_load32(counts+4)==first+2) {return 26;}extra=2;}
    si_pending=0;if !si_forced {esp_radio_cb_ints_off(3,0,0,0,0,0,0,0);}if !si_expect(si_trigger() && esp32_load32(counts+4)==first+extra) {return 18;}if !si_forced {esp_radio_cb_ints_on(3,0,0,0,0,0,0,0);}
    si_pending=5;esp_radio_irq(1);esp_radio_irq(-1);esp_radio_irq(32);if !si_expect(esp32_load32(counts+4)==first+extra) {return 19;}
    if !si_expect(!esp_radio_cb_clear_intr(2,0,0,0,0,0,0,0) && si_trigger() && esp32_load32(counts+4)==first+extra+mac) {return 20;}
    if !si_expect(!esp_radio_s3_irq_deinit() && !esp_radio_isr && !esp_radio_isr_arg && esp_irq_count==30 && esp32_load32(esp_radio_route(0))==17 && esp32_load32(esp_radio_route(2))==18 && esp_irq_soft_handler==esp32_callback(si_soft) && esp32_irq_enabled()==mask) {return 21;}
    if !si_expect(si_trigger() && esp32_load32(counts+4)==first+extra+mac && !esp32_load32(counts+8)) {return 22;}
    if !si_expect(!esp_radio_resources_end(handler) && !esp_radio_owner && esp_sdk_heap_free()==available) {return 23;}
    i=3;while i<33 {esp_irq_detach(i);i=i+1;}esp32_store32(esp_radio_route(0),r0);esp32_store32(esp_radio_route(2),r2);esp32_irq_save();esp_irq_soft_handler=soft_before;esp32_irq_clear(128);esp32_irq_mask(mask_before);
    esp_uart_write("PASS: S3 dual-source vendor IRQ ownership, capacity, C ABI and publication checks=");esp_uart_hex(si_checks);esp_uart_write("\r\n");return 0;
}
