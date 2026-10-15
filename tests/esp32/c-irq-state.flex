import "../../lib/platform/esp32.flex";
global saved_irq_ps=0;
fn mask_cb(a,b,c,d,e,f,g,h) {saved_irq_ps=esp32_irq_save();return 0;}
fn restore_cb(a,b,c,d,e,f,g,h) {esp32_irq_restore(saved_irq_ps);return 0;}
fn main() {
    let before=esp32_irq_save();esp32_irq_restore(before&~15);
    let f=esp32_external("c_irq_after_callback");
    if esp32_call32(f,esp32_callback32(mask_cb),0,0,0,0,0,0,0)!=15 {return 1;}
    let ps=esp32_irq_save();if (ps&15)!=15 {return 2;}esp32_irq_restore(ps);
    if esp32_call32(f,esp32_callback32(restore_cb),0,0,0,0,0,0,0)!=0 {return 3;}
    ps=esp32_irq_save();if ps&15 {return 4;}esp32_irq_restore(before);
    esp_uart_write("PASS: interrupt masks persist across C/Flex callbacks and calls\r\n");return 0;
}
