import "../../lib/platform/esp32s3-xip.flex";
import "../../lib/platform/esp32s3-sdk-preempt.flex";
import "../../lib/platform/esp32s3-radio-os.flex";
global ph_expect_hooks=0;
global ph_clock_override=0;
global ph_ref=0;
global ph_extra=0;
global ph_mode=0;
global ph_phase=0;
global ph_armed=0;
global ph_hooks=0;
global ph_masked=0;
global ph_done=0;
global ph_peer_done=0;
global ph_actor_result=0;
global ph_peer_result=0;
global ph_checks=0;
global ph_error=0;
global ph_baseline=0;
fn ph_clock() {if ph_clock_override {return esp32_external("phy_clock_register");}return 0x60026014;}
fn ph_get(i) {return esp32_load32(ph_ref+i*4);}
fn ph_set(i,v) {esp32_store32(ph_ref+i*4,v);return 0;}
fn ph_check(ok,code) {ph_checks=ph_checks+1;if !ok && !ph_error {ph_error=code;esp_uart_write("PHY PREEMPT FAIL ");esp_uart_hex(code);esp_uart_write(" mode=");esp_uart_hex(ph_mode);esp_uart_write(" Cbad=");esp_uart_hex(ph_get(0));esp_uart_write(" refs/clocks=");esp_uart_hex(esp_radio_phy_refs);esp_uart_hex(esp_radio_phy_clock_refs);esp_uart_write(" clock/heap/base/pointers=");esp_uart_hex(esp32_load32(ph_clock()));esp_uart_hex(esp_sdk_heap_free());esp_uart_hex(ph_baseline);esp_uart_hex(esp_radio_phy_cal);esp_uart_hex(esp_radio_phy_init_data);esp_uart_write("\r\n");}return ok;}
fn ph_soft(source) {if ph_get(7) {ph_set(0,ph_get(0)|32);}esp_sdk_reschedule_request();return 0;}
fn ph_gate(point) {
    if !ph_armed || point!=ph_mode {return 0;}ph_armed=0;ph_hooks=ph_hooks+1;ph_phase=point;let ps=esp32_irq_save();if ps&15 {ph_masked=ph_masked+1;}esp32_irq_restore(ps);esp32_irq_raise(128);
    if !(ps&15) {let begin=esp32_cycles();while !ph_peer_done && ((esp32_cycles()-begin)&4294967295)<8000000 {}}return 0;
}
fn ph_call_on() {return esp_radio_cb_phy_on(0,0,0,0,0,0,0,0);}
fn ph_call_off() {return esp_radio_cb_phy_off(0,0,0,0,0,0,0,0);}
fn ph_peer(a,b,c,d,e,f,g,h) {
    while !ph_phase && !ph_done {}
    if ph_mode==1 {ph_peer_result=esp_radio_phy_buffers_init();}
    else if ph_mode==4 {ph_peer_result=ph_call_off();}
    else if ph_mode==5 {ph_peer_result=ph_call_on();}
    else {ph_peer_result=esp_radio_phy_enable();}ph_peer_done=1;return 0;
}
fn ph_actor(a,b,c,d,e,f,g,h) {
    if ph_mode==1 {ph_actor_result=esp_radio_phy_buffers_init();}
    if ph_mode==2 {ph_actor_result=esp_radio_phy_enable();}
    if ph_mode==3 {ph_actor_result=esp_radio_phy_disable();}
    if ph_mode==4 {ph_actor_result=ph_call_on();}
    if ph_mode==5 {ph_actor_result=ph_call_off();}
    if ph_mode==6 {ph_actor_result=esp_radio_phy_release_buffers();}ph_done=1;return 0;
}
fn ph_join(t) {while load64(t+544)!=2 {esp_sdk_yield();}return esp_sdk_task_reap(t);}
fn ph_reset() {let j=0;while j<8 {esp32_store32(ph_extra+j*4,0);j=j+1;}let i=0;while i<16 {ph_set(i,0);i=i+1;}if ph_clock_override {ph_set(14,ph_clock());}ph_phase=0;ph_armed=1;ph_done=0;ph_peer_done=0;ph_actor_result= -99;ph_peer_result= -99;return 0;}
fn ph_validate(active) {return esp32_call32(esp32_external("phy_peer_validate"),active,0,0,0,0,0,0,0);}
fn main() {
    if esp_sdk_heap_init(esp_sdk_heap_min(),esp_sdk_heap_max()-esp_sdk_heap_min()) || esp_sdk_task_init() {return 1;}esp_irq_enable();ph_ref=esp32_external("phy_peer");ph_extra=esp32_external("s3_phy_extra");ph_gate(0);
    if esp_irq_software(esp32_callback(ph_soft)) || esp_sdk_preempt_start(5000) {return 2;}
    esp32_store32(ph_clock(),(esp32_load32(ph_clock())&~0x78078f)|0x2000000);let baseline=esp_sdk_heap_free();ph_baseline=baseline;ph_mode=1;
    while ph_mode<=6 {
        esp_uart_write("PHY CASE ");esp_uart_hex(ph_mode);esp_uart_write("\r\n");ph_reset();
        if ph_mode==3 && esp_radio_phy_enable() {return 3;}if ph_mode==5 && ph_call_on() {return 4;}if ph_mode==6 && esp_radio_phy_buffers_init() {return 5;}
        // Both dependent workers must exist before either can preempt main.
        let setup_ps=esp32_irq_save();let peer=esp_sdk_task_create(esp32_callback32(ph_peer),0,8192,5);let actor=esp_sdk_task_create(esp32_callback32(ph_actor),0,8192,5);esp32_irq_restore(setup_ps);if !peer || !actor {return 6;}ph_join(actor);ph_join(peer);
        let refs=1;let active=1;let registrations=1;let wakes=0;let closes=0;let rx=0;
        if ph_mode==1 {refs=0;active=0;registrations=0;}
        if ph_mode==2 {refs=2;}
        if ph_mode==3 {wakes=1;closes=1;}
        if ph_mode==4 {refs=0;active=0;closes=1;}
        if ph_mode==5 {wakes=1;closes=1;rx=1;}
        ph_check(!ph_actor_result && !ph_peer_result && esp_radio_phy_refs==refs && esp_radio_phy_clock_refs==refs && esp_radio_phy_cal && esp_radio_phy_init_data && esp_radio_phy_calibrated==(ph_mode!=1) && ph_get(1)==registrations && ph_get(2)==wakes && ph_get(3)==closes && ph_get(6)==rx && !ph_validate(active) && esp_radio_phy_digital && esp32_load32(ph_extra)==registrations && esp32_load32(ph_extra+4)==closes && esp32_load32(ph_extra+8)==wakes && esp32_load32(ph_extra+12)==closes && esp_radio_phy_digital_valid==(closes>wakes),100+ph_mode);if ph_error {return ph_error;}
        if ph_expect_hooks {ph_check(!ph_armed,200+ph_mode);}if ph_mode==5 {ph_call_off();}else {while esp_radio_phy_refs {esp_radio_phy_disable();}}
        ph_check(!esp_radio_phy_release_buffers() && !esp_radio_phy_cal && !esp_radio_phy_init_data && !esp_radio_phy_digital && !esp_radio_phy_digital_valid && !esp_radio_phy_calibrated && !esp_radio_phy_refs && !esp_radio_phy_clock_refs && !ph_get(0) && esp_sdk_heap_free()==baseline && (!ph_clock_override || (esp32_load32(ph_clock())&0x278078f)==0x2000000),300+ph_mode);if ph_error {return ph_error;}ph_mode=ph_mode+1;
    }
    // Recoverable direct/facade preparation must never publish half a pair or
    // leak a clock when either independent allocation fails.
    ph_mode=10;ph_reset();let remaining=64;while remaining<=2128 {
        let held=esp_sdk_malloc(baseline-remaining);if !held {return 7;}let free=esp_sdk_heap_free();let clock=esp32_load32(ph_clock());
        ph_check(esp_radio_phy_enable()== -12 && esp_radio_phy_buffers_init()== -12 && !esp_radio_phy_cal && !esp_radio_phy_init_data && !esp_radio_phy_digital && !esp_radio_phy_digital_valid && !esp_radio_phy_calibrated && !esp_radio_phy_refs && !esp_radio_phy_clock_refs && !ph_get(1) && !ph_get(2) && esp32_load32(ph_clock())==clock && esp_sdk_heap_free()==free,210);if ph_error {return ph_error;}esp_sdk_free(held);if remaining==64 {remaining=512;}else if remaining==512 {remaining=2000;}else if remaining==2000 {remaining=2128;}else {remaining=2129;}
    }
    ph_reset();ph_set(13,0x55);ph_check(!esp_radio_phy_buffers_init() && !esp_radio_phy_calibrated && !ph_get(1),211);let free=esp_sdk_heap_free();let cal=esp_radio_phy_cal;let data=esp_radio_phy_init_data;
    ph_check(!esp_radio_phy_buffers_init() && esp_sdk_heap_free()==free && !esp_radio_phy_enable() && ph_get(1)==1 && !ph_get(2) && esp_radio_phy_result==0x55 && esp_radio_phy_calibrated,212);if ph_error {return ph_error;}
    ph_check(esp_radio_phy_release_buffers()== -16 && esp_radio_phy_cal==cal && esp_radio_phy_init_data==data && esp_sdk_heap_free()==free,213);
    esp_radio_phy_disable();let round=0;while round<3 {ph_check(!esp_radio_phy_enable() && esp_radio_phy_cal==cal && esp_radio_phy_init_data==data && esp_radio_phy_result==0x55 && !ph_validate(1),214);esp_radio_phy_disable();round=round+1;}
    ph_check(ph_get(1)==1 && ph_get(2)==3 && ph_get(3)==4 && !esp_radio_phy_release_buffers() && esp_sdk_heap_free()==baseline,215);if ph_error {return ph_error;}
    ph_reset();let adc_clock=esp32_load32(ph_clock());esp_adc_busy=1;ph_check(esp_radio_phy_enable()== -16 && esp_radio_phy_clock(1)== -16 && !esp_radio_phy_refs && !esp_radio_phy_clock_refs && !ph_get(1) && !esp_radio_phy_cal && !esp_radio_phy_init_data && !esp_radio_phy_digital && esp32_load32(ph_clock())==adc_clock && esp_sdk_heap_free()==baseline,224);esp_adc_busy=0;
    esp_radio_phy_clock_refs=9223372036854775807;let saved_clock=esp32_load32(ph_clock());ph_check(esp_radio_phy_enable()== -75 && esp_radio_phy_clock(1)== -75 && esp32_load32(ph_clock())==saved_clock && !esp_radio_phy_cal,225);esp_radio_phy_clock_refs=0;if ph_error {return ph_error;}
    // Independent clock guards survive RF shutdown, and nested masks retain PS.
    ph_reset();esp_radio_phy_clock(1);esp_radio_phy_clock(1);ph_check(esp_radio_phy_release_buffers()== -16 && esp_radio_phy_clock_refs==2,216);
    let ps=esp32_irq_save();ph_check(!esp_radio_phy_enable() && esp_radio_phy_clock_refs==3,217);let nested=esp32_irq_save();ph_check((nested&15)==15,218);esp32_irq_restore(nested);esp_radio_phy_disable();nested=esp32_irq_save();ph_check((nested&15)==15 && !esp_radio_phy_refs && esp_radio_phy_clock_refs==2 && (!ph_clock_override || (esp32_load32(ph_clock())&0x78078f)==0x78078f),219);esp32_irq_restore(nested);esp32_irq_restore(ps);
    esp_radio_phy_disable();ph_check(esp_radio_phy_clock_refs==2 && ph_get(3)==1,220);esp_radio_phy_clock(0);esp_radio_phy_clock(0);esp_radio_phy_clock(0);ph_check(!esp_radio_phy_clock_refs && !esp_radio_phy_release_buffers() && esp_sdk_heap_free()==baseline && !ph_get(0),221);if ph_error {return ph_error;}
    if ph_expect_hooks {ph_check(ph_hooks==6 && ph_masked==6,222);}ph_check(!esp_sdk_preempt_stop(),223);if ph_error {return ph_error;}
    esp_uart_write("PASS: PHY masked calibration/wakeup/close/RX, paired allocation rollback, references and buffer lifetime; checks=");esp_uart_hex(ph_checks);esp_uart_write(" hooks=");esp_uart_hex(ph_hooks);esp_uart_write(" masked=");esp_uart_hex(ph_masked);esp_uart_write("\r\n");return 0;
}
