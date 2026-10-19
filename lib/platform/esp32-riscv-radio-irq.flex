import "esp32-riscv-radio-lifecycle.flex";
// Vendor set_intr requests MAC0/PWR2 on private CPU line1, priority1.
// Use only their routes; the shared CPU line also belongs to application IRQs.
global esp_radio_isr=0;
global esp_radio_isr_arg=0;
global esp_radio_irq_count=0;
fn esp_radio_irq_status(){if rv_hal_chip==5{return 0x600c20f8;}return 0x60010134;}
fn esp_radio_irq(source){
 if source!=0 && source!=2{return 0;}let ps=esp32_irq_save();
 if esp_radio_owner!=1 || !esp_radio_isr || esp32_load32(esp_radio_route(source))!=1 || !(esp32_load32(esp_radio_irq_status())&(1<<source)){esp32_irq_restore(ps);return 0;}
 esp_radio_irq_count=esp_radio_irq_count+1;esp32_call32(esp_radio_isr,esp_radio_isr_arg,0,0,0,0,0,0,0);esp32_irq_restore(ps);return 0;
}
// The native handler table is only one ownership source. An enabled raw
// route can belong to a C/ROM user; never replace or mask that live route.
fn esp_radio_riscv_claimable(source,handler){
 let result=esp_radio_irq_can_claim(source,handler);if result{return result;}let route=esp32_load32(esp_radio_route(source))&31;
 if route && (esp32_irq_enabled()&(1<<route)){
  let own=load64(esp_radio_irq_routes+source*16);if !own || route!=1{return -16;}
 }return 0;
}
fn esp_radio_cb_set_intr(a,b,c,d,e,f,g,h){
 if a || (b!=0 && b!=2) || c!=1 || d!=1{return -22;}let ps=esp32_irq_save();if esp_radio_owner!=1{esp32_irq_restore(ps);return -22;}
 let result=esp_radio_riscv_claimable(b,esp32_iram_callback(esp_radio_irq));if !result{result=esp_radio_irq_claim(b);}if result{esp32_irq_restore(ps);return result;}
 let route=0;if esp_radio_isr && esp_irq_handler(b)==esp32_iram_callback(esp_radio_irq){route=1;}esp32_store32(esp_radio_route(b),route);esp32_irq_restore(ps);return 0;
}
fn esp_radio_cb_clear_intr(a,b,c,d,e,f,g,h){
 if (a!=0 && a!=2) || b!=1{return -22;}let ps=esp32_irq_save();if esp_radio_owner!=1 || !esp_radio_irq_routes || !load64(esp_radio_irq_routes+a*16){esp32_irq_restore(ps);return -22;}
 let handler=esp_irq_handler(a);if handler && handler!=esp32_iram_callback(esp_radio_irq){esp32_irq_restore(ps);return -16;}let result=esp_radio_riscv_claimable(a,esp32_iram_callback(esp_radio_irq));if result{esp32_irq_restore(ps);return result;}esp32_store32(esp_radio_route(a),0);esp32_irq_restore(ps);return 0;
}
fn esp_radio_cb_set_isr(a,b,c,d,e,f,g,h){
 if a<0 || a>1 || b<=0 || b>>32{return -22;}let ps=esp32_irq_save();if esp_radio_owner!=1{esp32_irq_restore(ps);return -22;}
 let handler=esp32_iram_callback(esp_radio_irq);let result=esp_radio_riscv_claimable(0,handler);if !result{result=esp_radio_riscv_claimable(2,handler);}if result{esp32_irq_restore(ps);return result;}
 result=esp_irq_reserve(!esp_irq_handler(0)+!esp_irq_handler(2));if result{esp32_irq_restore(ps);return result;}
 result=esp_radio_irq_claim(0);if !result{result=esp_radio_irq_claim(2);}if result{esp32_irq_restore(ps);return result;}
 esp_radio_isr=b;esp_radio_isr_arg=c;result=esp_irq_attach(0,handler);if !result{result=esp_irq_attach(2,handler);}esp32_irq_restore(ps);return result;
}
fn esp_radio_cb_ints_on(a,b,c,d,e,f,g,h){
 if a!=2{return -22;}let ps=esp32_irq_save();let handler=esp32_iram_callback(esp_radio_irq);
 if esp_radio_owner!=1 || !esp_radio_isr || esp_irq_handler(0)!=handler || esp_irq_handler(2)!=handler{esp32_irq_restore(ps);return -22;}
 let result=esp_radio_riscv_claimable(0,handler);if !result{result=esp_radio_riscv_claimable(2,handler);}if result{esp32_irq_restore(ps);return result;}
 esp32_store32(esp_radio_route(0),1);esp32_store32(esp_radio_route(2),1);esp32_irq_mask(esp32_irq_enabled()|2);esp32_irq_restore(ps);return 0;
}
fn esp_radio_cb_ints_off(a,b,c,d,e,f,g,h){
 if a!=2{return -22;}let ps=esp32_irq_save();let handler=esp32_iram_callback(esp_radio_irq);
 if esp_radio_owner!=1 || esp_irq_handler(0)!=handler || esp_irq_handler(2)!=handler{esp32_irq_restore(ps);return -22;}
 let result=esp_radio_riscv_claimable(0,handler);if !result{result=esp_radio_riscv_claimable(2,handler);}if result{esp32_irq_restore(ps);return result;}
 esp32_store32(esp_radio_route(0),0);esp32_store32(esp_radio_route(2),0);esp32_irq_restore(ps);return 0;
}
