// Physical-radio oracle: application IRQ, timer and SDK allocations must
// survive every radio lifetime; domain-owned bytes must recover exactly.
import "../../lib/platform/esp32-radio-clock.flex";
import "../../lib/platform/esp32-sdk-sync.flex";
import "../../lib/platform/esp32-sdk-timer.flex";
import "../../lib/platform/esp32-irq.flex";
global lp_irqs=0;
global lp_ticks=0;
global lp_sem=0;
global lp_guard=0;
global lp_key=0;
global lp_baseline=0;
fn lp_word(label,value) {esp_uart_write(label);esp_uart_hex(value);esp_uart_write("\r\n");return 0;}
fn lp_irq(source) {if source==14 && esp_timer_pending(0) {esp_timer_ack(0,1);lp_irqs=lp_irqs+1;}return 0;}
fn lp_tick(a,b,c,d,e,f,g,h) {lp_ticks=lp_ticks+1;return 0;}
fn lp_init() {
    esp_radio_clock_init();if esp_sdk_heap_init(0x3ffc8000,98304) || esp_sdk_task_init() {return 1;}
    lp_sem=esp_sdk_sem_create(1,1);lp_guard=esp_sdk_malloc(80);if !lp_sem || !lp_guard {return 2;}let i=0;while i<80 {store8(lp_guard+i,(i*31+9)&255);i=i+1;}
    if esp_timer_init(0,80,0) || esp_timer_alarm(0,20000,1) || esp_irq_attach(14,esp32_iram_callback(lp_irq)) || esp_timer_start(0) {return 3;}esp_irq_enable();lp_baseline=esp_sdk_heap_free();return 0;
}
fn lp_shared() {if esp_sdk_timer_init() {return 1;}lp_key=alloc(8);if esp_sdk_timer_setfn(lp_key,esp32_callback32(lp_tick),0) || esp_sdk_timer_arm(lp_key,5000,1) {return 2;}lp_baseline=esp_sdk_heap_free();return 0;}
fn lp_check() {
    if esp_sdk_heap_free()!=lp_baseline {lp_word("HEAP LEAK ",lp_baseline-esp_sdk_heap_free());return 1;}
    if esp_radio_owner || esp_radio_phy_refs || esp_radio_phy_clock_refs || esp_radio_phy_cal || esp_radio_phy_init_data || esp_irq_count!=1 || esp_irq_handler(14)!=esp32_iram_callback(lp_irq) || !(esp32_irq_enabled()&2) {return 2;}
    if !esp_sdk_sem_take(lp_sem,0) || !esp_sdk_sem_give(lp_sem) {return 3;}let i=0;while i<80 {if load8(lp_guard+i)!=((i*31+9)&255) {return 4;}i=i+1;}
    let before=lp_irqs;let tick=lp_ticks;esp_sdk_delay(30);if lp_irqs<=before || (lp_key && lp_ticks<=tick) {return 5;}return 0;
}
