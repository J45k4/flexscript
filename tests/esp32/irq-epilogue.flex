global tail_seen=0;
global tail_error=0;
fn esp_irq_dispatch(pending) {if pending&128 {esp32_irq_clear(128);}return 0;}
fn esp_irq_epilogue(ps) {
    if ps&15 {tail_error=1;}if esp32_load32(esp32_state()+16) {tail_error=2;}
    if (esp32_irq_save()&15)!=15 {tail_error=3;}tail_seen=tail_seen+1;return 0;
}
fn main() {
    if esp32_preempt_supported()!=1 {return 1;}esp32_irq_mask(128);esp32_irq_restore(0);esp32_irq_raise(128);while !tail_seen {}
    let ps=esp32_irq_save();if tail_seen!=1 || tail_error || (ps&15) {return 2;}return 0;
}
