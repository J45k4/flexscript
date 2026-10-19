import "../../lib/platform/esp32c3-radio-os.flex";
global ri_observed=0;global ri_bad=0;global ri_foreign_changed=0;global ri_probe_set_intr=1;
fn ri_vendor(a,b,c,d,e,f,g,h){if a!=0x12345678 || !esp32_load32(esp32_state()+16){ri_bad=1;}return 0;}
fn ri_application(source){return 0;}
fn ri_observer(source){let handler=esp32_iram_callback(esp_radio_irq);if esp_radio_isr!=esp32_callback32(ri_vendor) || esp_radio_isr_arg!=0x12345678 || esp_irq_handler(0)!=handler || esp_irq_handler(2)!=handler || esp32_load32(esp_radio_route(0))!=1 || esp32_load32(esp_radio_route(2))!=1{ri_bad=2;}esp32_call32(esp_radio_isr,esp_radio_isr_arg,0,0,0,0,0,0,0);ri_observed=1;return 0;}
fn main(){
 let arena=esp_sdk_heap_min();if esp_sdk_heap_init(arena,esp_sdk_heap_max()-arena) || esp_libc_stdio_init() || esp_libc_rom_init() || esp_sdk_task_init(){return 1;}let before=esp_sdk_heap_free();if esp_radio_os_init(){return 2;}
 let callback=esp32_callback32(ri_vendor);let route0=esp32_load32(esp_radio_route(0));let route2=esp32_load32(esp_radio_route(2));
 let saved_mask=esp32_irq_enabled();esp32_store32(esp_radio_route(0),6);esp32_irq_mask(saved_mask|64);if ri_probe_set_intr && (esp_radio_cb_set_intr(0,0,1,1,0,0,0,0)!=-16 || esp32_load32(esp_radio_route(0))!=6){return 16;}let refused=esp_radio_cb_set_isr(0,callback,0x12345678,0,0,0,0,0);
 if refused!=-16 || esp_radio_isr || esp32_load32(esp_radio_route(0))!=6 || esp32_load32(esp_radio_route(2))!=route2 || esp32_irq_enabled()!=(saved_mask|64){ri_foreign_changed=(esp32_load32(esp_radio_route(0))!=6)|((esp_radio_isr!=0)<<1)|((esp32_irq_enabled()!=(saved_mask|64))<<2);return 15;}esp32_irq_mask(saved_mask);esp32_store32(esp_radio_route(0),route0);
 if esp_irq_attach(0,esp32_iram_callback(ri_application)){return 3;}if esp_radio_cb_set_isr(0,callback,0,0,0,0,0,0)!=-16 || esp_radio_isr || esp_irq_handler(2) || esp32_load32(esp_radio_route(2))!=route2{return 4;}esp_irq_detach(0);
 let source=1;let filled=0;while filled<31{if source!=2{if esp_irq_attach(source,esp32_iram_callback(ri_application)){return 5;}filled=filled+1;}source=source+1;}
 if esp_radio_cb_set_isr(0,callback,0,0,0,0,0,0)!=-12 || esp_radio_isr || esp_irq_handler(0) || esp_irq_handler(2) || esp_irq_count!=31{return 6;}
 source=1;while source<34{esp_irq_detach(source);source=source+1;}
 if esp_radio_cb_set_intr(1,0,1,1,0,0,0,0)!=-22 || esp_radio_cb_set_intr(0,3,1,1,0,0,0,0)!=-22 || esp_radio_cb_set_intr(0,0,2,1,0,0,0,0)!=-22{return 7;}
 if esp_radio_cb_set_intr(0,0,1,1,0,0,0,0) || esp_radio_cb_set_intr(0,2,1,1,0,0,0,0) || esp32_load32(esp_radio_route(0)) || esp32_load32(esp_radio_route(2)){return 8;}
 if esp_irq_software(esp32_iram_callback(ri_observer)){return 9;}esp32_irq_raise(128);
 if esp_radio_cb_set_isr(1,callback,0x12345678,0,0,0,0,0) || esp_radio_cb_ints_off(2,0,0,0,0,0,0,0) || esp32_load32(esp_radio_route(0)) || esp32_load32(esp_radio_route(2)) || !(esp32_irq_enabled()&2){return 10;}
 let owned_mask=esp32_irq_enabled();esp32_store32(esp_radio_route(2),6);esp32_irq_mask(owned_mask|64);
 if esp_radio_cb_ints_on(2,0,0,0,0,0,0,0)!=-16 || esp_radio_cb_ints_off(2,0,0,0,0,0,0,0)!=-16 || esp_radio_cb_clear_intr(2,1,0,0,0,0,0,0)!=-16 || esp_radio_cb_set_intr(0,2,1,1,0,0,0,0)!=-16 || esp_radio_cb_set_isr(0,callback,0xabcdef,0,0,0,0,0)!=-16 || esp_radio_isr_arg!=0x12345678 || esp32_load32(esp_radio_route(0)) || esp32_load32(esp_radio_route(2))!=6 || esp32_irq_enabled()!=(owned_mask|64){return 17;}esp32_store32(esp_radio_route(2),0);esp32_irq_mask(owned_mask);
 if esp_radio_cb_ints_on(4,0,0,0,0,0,0,0)!=-22 || esp_radio_cb_ints_on(2,0,0,0,0,0,0,0){return 11;}esp_sdk_task_unmask();let start=esp32_cycles();while !ri_observed && ((esp32_cycles()-start)&4294967295)<1000000{}esp32_irq_save();if !ri_observed || ri_bad{return 12;}
 if esp_radio_cb_clear_intr(0,1,0,0,0,0,0,0) || esp32_load32(esp_radio_route(0)) || esp32_load32(esp_radio_route(2))!=1{return 13;}
 esp_irq_soft_handler=0;esp32_irq_mask(esp32_irq_enabled()&~128);esp32_irq_clear(128);
 if esp_radio_resources_end(esp32_iram_callback(esp_radio_irq)) || esp_sdk_heap_free()!=before || esp_irq_handler(0) || esp_irq_handler(2) || esp32_load32(esp_radio_route(0))!=route0 || esp32_load32(esp_radio_route(2))!=route2{return 14;}return 0;
}
