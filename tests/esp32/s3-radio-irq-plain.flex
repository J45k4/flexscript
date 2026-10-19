import "../../lib/platform/esp32s3-radio-irq.flex";
global sp_runs=0;
fn sp_soft(source) {sp_runs=sp_runs+1;esp_radio_irq(0);esp_radio_irq(2);return 0;}
fn main() {
    let start=esp_sdk_heap_min();if esp_sdk_heap_init(start,esp_sdk_heap_max()-start) || esp_sdk_task_init() || esp_radio_resources_begin(1) {return 1;}
    let old0=esp32_load32(esp_radio_route(0));let old2=esp32_load32(esp_radio_route(2));
    let callback=esp32_external("c_s3_irq_old");let counts=esp32_external("c_s3_irq_counts");let arg=alloc(12);esp32_store32(arg,0x4f4c4421);esp32_store32(arg+4,0x13572468);esp32_store32(arg+8,0x24681357);
    if esp_radio_cb_set_isr(0,callback,arg,0,0,0,0,0) || esp_irq_handler(0)!=esp32_callback(esp_radio_irq) || esp_irq_handler(2)!=esp32_callback(esp_radio_irq) {return 2;}
    let mask=esp32_irq_enabled();if esp_radio_cb_ints_off(3,0,0,0,0,0,0,0) || esp32_irq_enabled()!=mask || esp32_load32(esp_radio_route(0))!=6 || esp32_load32(esp_radio_route(2))!=6 {return 3;}
    esp_radio_irq(0);esp_radio_irq(2);if esp32_load32(counts) || esp_radio_cb_ints_on(3,0,0,0,0,0,0,0) {return 4;}
    esp_irq_software(esp32_callback(sp_soft));let bits=esp32_load32(0x600c218c)&5;let expected=(bits&1)+((bits>>2)&1);esp32_irq_mask(esp32_irq_enabled()&~2);esp32_irq_raise(128);esp32_irq_restore(0);
    let before=esp32_cycles();while !sp_runs && ((esp32_cycles()-before)&4294967295)<1000000 {}esp32_irq_save();
    if sp_runs!=1 || esp32_load32(counts)!=expected || esp32_load32(counts+8) || esp_radio_irq_count!=expected {return 5;}
    if esp_radio_s3_irq_deinit() || esp_radio_resources_end(esp32_callback(esp_radio_irq)) || esp_radio_owner || esp_radio_isr || esp_radio_isr_arg || esp32_load32(esp_radio_route(0))!=old0 || esp32_load32(esp_radio_route(2))!=old2 {return 6;}
    esp_irq_soft_handler=0;esp32_irq_clear(128);esp32_irq_mask(0);esp_uart_write("PASS: plain S3 vendor IRQ C callback, both routes, masked software delivery and cleanup\r\n");return 0;
}
