import "esp32-sdk-task-core.flex";
// Opt-in CPU0 scheduling. The chip adapter supplies a separate idle tick timer.
// ISR callbacks request a switch; only the compiler IRQ tail performs it.
global esp_sdk_preempt_enabled=0;
global esp_sdk_preempt_ticks=0;
global esp_sdk_preempt_switches=0;
global esp_sdk_preempt_saved=0;
global esp_sdk_preempt_quantum=0;
// Saved words: config,alarm low/high,load low/high,counter low/high,route,
// CPU INTENABLE. No IRQ-enable ownership is taken unless the tick timer is idle.
fn esp_sdk_preempt_tick(source) {
    if esp_sdk_preempt_enabled && esp_timer_pending(esp_sdk_preempt_timer()) {esp_timer_ack(esp_sdk_preempt_timer(),0);esp_timer_alarm(esp_sdk_preempt_timer(),esp_timer_read(esp_sdk_preempt_timer())+esp_sdk_preempt_quantum,0);esp_sdk_preempt_ticks=esp_sdk_preempt_ticks+1;esp_sdk_reschedule_request();}return 0;
}
fn esp_irq_epilogue(interrupted_ps) {
    if !esp_sdk_preempt_enabled || !esp_sdk_reschedule_requested || !esp_sdk_current || esp_sdk_irq_blocked(interrupted_ps) {return 0;}
    esp_sdk_reschedule_requested=0;let previous=esp_sdk_current;let next=esp_sdk_task_choose(previous,esp_sdk_now());
    // Never enter a blocking yield from an IRQ tail. If every task is asleep,
    // The trap return must first restore interrupts so device IRQs can satisfy their waits.
    if next && next!=previous {esp_sdk_current=next;esp_sdk_context_select(next);esp_sdk_yields=esp_sdk_yields+1;esp_sdk_preempt_switches=esp_sdk_preempt_switches+1;esp32_switch(previous,next);}return 0;
}
fn esp_sdk_preempt_start(quantum_us) {
    if !esp32_preempt_supported() || !esp_sdk_current || esp32_load32(esp32_state()+16) {return -16;}
    if quantum_us<1000 || quantum_us>1000000 {return -22;}let ps=esp32_irq_save();
    let base=esp_timer_base(esp_sdk_preempt_timer());let source=esp_timer_source(esp_sdk_preempt_timer());let enable_reg=esp_sdk_preempt_enable_reg();let route=esp_sdk_preempt_route();
    if esp_sdk_preempt_enabled || esp_irq_handler(source) || (esp32_load32(base)&(1<<31)) || (esp32_load32(enable_reg)&esp_sdk_preempt_interrupt_bit()) || esp_timer_pending(esp_sdk_preempt_timer()) {esp32_irq_restore(ps);return -16;}
    if !esp_sdk_preempt_saved {esp_sdk_preempt_saved=alloc(80);if esp_sdk_preempt_saved<=0 {esp_sdk_preempt_saved=0;esp32_irq_restore(ps);return -12;}}
    let saved=esp_sdk_preempt_saved;store64(saved,esp32_load32(base));store64(saved+8,esp32_load32(base+16));store64(saved+16,esp32_load32(base+20));store64(saved+24,esp32_load32(base+24));store64(saved+32,esp32_load32(base+28));
    let read=esp_timer_read_words(esp_sdk_preempt_timer(),saved+72);if read {esp32_irq_restore(ps);return read;}store64(saved+40,esp32_load32(saved+72));store64(saved+48,esp32_load32(saved+76));store64(saved+56,esp32_load32(route));store64(saved+64,esp32_irq_enabled());
    let result=esp_irq_attach(source,esp32_callback(esp_sdk_preempt_tick));if result {esp32_irq_restore(ps);return result;}
    esp_sdk_preempt_timer_init();esp_timer_alarm(esp_sdk_preempt_timer(),quantum_us,0);esp_sdk_preempt_quantum=quantum_us;esp_sdk_reschedule_requested=0;esp_sdk_preempt_enabled=1;esp_timer_start(esp_sdk_preempt_timer());esp32_irq_restore(ps);return 0;
}
fn esp_sdk_preempt_stop() {
    if esp32_load32(esp32_state()+16) {return -16;}let ps=esp32_irq_save();if !esp_sdk_preempt_enabled {esp32_irq_restore(ps);return 0;}
    esp_sdk_preempt_enabled=0;esp_timer_stop(esp_sdk_preempt_timer());esp_reg_update(esp_sdk_preempt_enable_reg(),esp_sdk_preempt_interrupt_bit(),0);esp_timer_ack(esp_sdk_preempt_timer(),0);esp_irq_detach(esp_timer_source(esp_sdk_preempt_timer()));
    let saved=esp_sdk_preempt_saved;let base=esp_timer_base(esp_sdk_preempt_timer());esp_timer_set_words(esp_sdk_preempt_timer(),load64(saved+40),load64(saved+48));esp32_store32(base+16,load64(saved+8));esp32_store32(base+20,load64(saved+16));esp32_store32(base+24,load64(saved+24));esp32_store32(base+28,load64(saved+32));esp32_store32(base,load64(saved));esp32_store32(esp_sdk_preempt_route(),load64(saved+56));
    if !esp_irq_count {esp32_irq_mask((esp32_irq_enabled()&~2)|(load64(saved+64)&2));}esp_sdk_reschedule_requested=0;esp32_irq_restore(ps);return 0;
}
