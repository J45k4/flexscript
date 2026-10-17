// Exhaust only this firmware's native bump arena; no physical flash access.
import "../../lib/platform/esp32-xip.flex";
import "../../lib/platform/esp32-bluetooth.flex";
global cap_called=0;
global cap_bad=0;
fn cap_app(source) {return 0;}
fn cap_vendor(a,b,c,d,e,f,g,h) {cap_called=cap_called+1;if a!=0x42 {cap_bad=1;}return 0;}
fn main() {
    if esp_sdk_heap_init(0x3ffc8000,98304) || esp_sdk_task_init() || esp_radio_resources_begin(2) {return 1;}esp_irq_enable();let base=esp32_state();let remaining=base+98304-esp32_load32(base)-256;if remaining<=0 || alloc(remaining)<=0 {return 2;}let bump=esp32_load32(base);let mask=esp32_irq_enabled();let route=esp32_load32(0x3ff00104);let route4=esp32_load32(0x3ff00104+4*4);let route6=esp32_load32(0x3ff00104+6*4);let route7=esp32_load32(0x3ff00104+7*4);let function=esp32_callback32(cap_vendor);
    if esp_irq_reserve(1)!= -12 || esp_irq_table || esp_irq_count || esp32_load32(base)!=bump || esp32_irq_enabled()!=mask {return 3;}
    if esp_irq_attach(0,esp32_callback(cap_app))!= -12 || esp_irq_table || esp_irq_count || esp32_load32(0x3ff00104)!=route {return 4;}
    if esp_radio_cb_set_isr(0,function,0x42,0,0,0,0,0)!= -12 || esp_radio_isr || esp_radio_isr_arg || load64(esp_radio_irq_routes) {return 5;}
    if esp_bt_set_isr(5,function,0x42,0,0,0,0,0)!= -12 || esp_bt_irq5 || esp_bt_arg5 || load64(esp_radio_irq_routes+6*16) || load64(esp_radio_irq_routes+7*16) || esp32_load32(0x3ff00104+6*4)!=route6 || esp32_load32(0x3ff00104+7*4)!=route7 {return 6;}
    if esp_bt_set_isr(8,function,0x42,0,0,0,0,0)!= -12 || esp_bt_irq8 || esp_bt_arg8 || load64(esp_radio_irq_routes+4*16) || esp32_load32(0x3ff00104+4*4)!=route4 {return 7;}
    if esp32_load32(base)!=bump || esp_irq_table || esp_irq_count || esp32_irq_enabled()!=mask || esp_irq_reserve(33)!= -22 {return 8;}
    // Software callbacks need no external IRQ-table allocation and still work.
    if esp_bt_set_isr(7,function,0x42,0,0,0,0,0) {return 9;}esp32_irq_raise(128);let start=esp32_cycles();while !cap_called && ((esp32_cycles()-start)&4294967295)<1000000 {}
    if cap_called!=1 || cap_bad || esp_irq_table || esp32_load32(base)!=bump || esp_radio_resources_end(esp32_iram_callback(esp_bt_irq)) || esp_irq_soft_handler || esp_radio_owner || esp_irq_reserve(0) {return 10;}
    let ps=esp32_irq_save();if ps&15 {return 11;}esp32_irq_restore(ps);esp_uart_write("PASS: IRQ native allocation failures preserve bindings/routes/enables; software dispatch remains available\r\n");return 0;
}
