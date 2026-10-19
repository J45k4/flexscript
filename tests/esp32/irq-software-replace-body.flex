global sr_old=0;
global sr_new=0;
global sr_bad=0;
fn sr_old_handler(source) {sr_old=sr_old+1;return 0;}
fn sr_new_handler(source) {sr_new=sr_new+1;if source!= -1 || esp32_load32(esp32_state()+16)!=1 {sr_bad=1;}return 0;}
fn main() {
    esp_irq_enable();let heap=esp32_load32(esp32_state());let ps=esp32_irq_save();esp32_irq_raise(128);if esp_irq_software(esp32_callback(sr_old_handler)) || (esp32_irq_pending()&128) {return 1;}esp32_irq_restore(ps);if sr_old || sr_new {return 2;}
    let repeat=0;while repeat<32 {
        ps=esp32_irq_save();if esp_irq_software(esp32_callback(sr_old_handler)) {return 3;}esp32_irq_raise(128);let mask=2;if repeat&1 {mask=15;}esp32_irq_restore(mask);
        if esp_irq_software(esp32_callback(sr_new_handler)) {return 4;}ps=esp32_irq_save();if (ps&15)!=mask || !(esp32_irq_pending()&128) || esp_irq_soft_handler!=esp32_callback(sr_new_handler) {return 5;}esp32_irq_restore(0);
        let begin=esp32_cycles();while sr_new<repeat*2+1 && ((esp32_cycles()-begin)&4294967295)<1000000 {}if sr_new!=repeat*2+1 || sr_old || sr_bad {return 6;}
        ps=esp32_irq_save();esp32_irq_raise(128);let handler=esp_irq_soft_handler;let enabled=esp32_irq_enabled();if esp_irq_software(0)!= -22 || esp_irq_software(4294967296)!= -22 || esp_irq_soft_handler!=handler || esp32_irq_enabled()!=enabled || !(esp32_irq_pending()&128) {return 7;}esp32_irq_restore(0);
        begin=esp32_cycles();while sr_new<repeat*2+2 && ((esp32_cycles()-begin)&4294967295)<1000000 {}if sr_new!=repeat*2+2 || sr_old || sr_bad {return 8;}repeat=repeat+1;
    }
    ps=esp32_irq_save();if (ps&15) || esp_irq_count || esp32_load32(esp32_state())!=heap || (esp32_irq_pending()&128) {return 9;}esp32_irq_restore(ps);esp_uart_write("PASS:64 software IRQ replacements/rejections, masked levels, initial stale clear and exact delivery\r\n");return 0;
}
