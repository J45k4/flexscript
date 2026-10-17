import "esp32s3-radio-lifecycle.flex";
// Wi-Fi OSI v9 uses one C callback/argument for MAC(source0) and PWR(source2).
// Both use this backend's shared CPU0 level-1 interrupt. Vendor interrupt IDs
// are private to the adapter; changing CPU INTENABLE would affect other users.
global esp_radio_isr=0;
global esp_radio_isr_arg=0;
global esp_radio_irq_count=0;
fn esp_radio_irq(source) {
    if source!=0 && source!=2 {return 0;}let ps=esp32_irq_save();
    if esp_radio_owner!=1 || !esp_radio_isr || esp32_load32(esp_radio_route(source))!=1 || !(esp32_load32(0x600c218c)&(1<<source)) {esp32_irq_restore(ps);return 0;}
    esp_radio_irq_count=esp_radio_irq_count+1;
    esp32_call32(esp_radio_isr,esp_radio_isr_arg,0,0,0,0,0,0,0);esp32_irq_restore(ps);return 0;
}
fn esp_radio_cb_set_intr(a,b,c,d,e,f,g,h) {
    if b!=0 && b!=2 {return -22;}let ps=esp32_irq_save();if esp_radio_owner!=1 {esp32_irq_restore(ps);return -22;}
    let result=esp_radio_irq_can_claim(b,esp32_callback(esp_radio_irq));if !result {result=esp_radio_irq_claim(b);}if result {esp32_irq_restore(ps);return result;}
    // Claim/save the old route before any publication. A route request alone
    // cannot expose an absent callback; set_isr publishes both sources.
    let route=6;if esp_radio_isr && esp_irq_handler(b)==esp32_callback(esp_radio_irq) {route=1;}
    esp32_store32(esp_radio_route(b),route);esp32_irq_restore(ps);return 0;
}
fn esp_radio_cb_clear_intr(a,b,c,d,e,f,g,h) {
    if a!=0 && a!=2 {return -22;}let ps=esp32_irq_save();if esp_radio_owner!=1 {esp32_irq_restore(ps);return -22;}
    if !esp_radio_irq_routes || !load64(esp_radio_irq_routes+a*16) {esp32_irq_restore(ps);return -22;}
    let handler=esp_irq_handler(a);if handler && handler!=esp32_callback(esp_radio_irq) {esp32_irq_restore(ps);return -16;}
    esp32_store32(esp_radio_route(a),6);esp32_irq_restore(ps);return 0;
}
fn esp_radio_cb_set_isr(a,b,c,d,e,f,g,h) {
    if a<0 || a>1 || b<=0 || b>>32 {return -22;}let ps=esp32_irq_save();if esp_radio_owner!=1 {esp32_irq_restore(ps);return -22;}
    let handler=esp32_callback(esp_radio_irq);let result=esp_radio_irq_can_claim(0,handler);
    if !result {result=esp_radio_irq_can_claim(2,handler);}if result {esp32_irq_restore(ps);return result;}
    result=esp_irq_reserve(!esp_irq_handler(0)+!esp_irq_handler(2));if result {esp32_irq_restore(ps);return result;}
    result=esp_radio_irq_claim(0);if !result {result=esp_radio_irq_claim(2);}if result {esp32_irq_restore(ps);return result;}
    // No task/ISR can observe a mixed pair or a half-attached registration.
    esp_radio_isr=b;esp_radio_isr_arg=c;result=esp_irq_attach(0,handler);
    if !result {result=esp_irq_attach(2,handler);}esp32_irq_restore(ps);return result;
}
fn esp_radio_cb_ints_on(a,b,c,d,e,f,g,h) {
    let ps=esp32_irq_save();let handler=esp32_callback(esp_radio_irq);
    if esp_radio_owner!=1 || !esp_radio_isr || esp_irq_handler(0)!=handler || esp_irq_handler(2)!=handler {esp32_irq_restore(ps);return -22;}
    esp32_store32(esp_radio_route(0),1);esp32_store32(esp_radio_route(2),1);
    esp32_irq_mask(esp32_irq_enabled()|2);esp32_irq_restore(ps);return 0;
}
fn esp_radio_cb_ints_off(a,b,c,d,e,f,g,h) {
    let ps=esp32_irq_save();let handler=esp32_callback(esp_radio_irq);
    if esp_radio_owner!=1 || esp_irq_handler(0)!=handler || esp_irq_handler(2)!=handler {esp32_irq_restore(ps);return -22;}
    esp32_store32(esp_radio_route(0),6);esp32_store32(esp_radio_route(2),6);
    esp32_irq_restore(ps);return 0;
}
fn esp_radio_s3_irq_deinit() {
    let ps=esp32_irq_save();if esp_radio_owner!=1 {esp32_irq_restore(ps);return -22;}
    esp_radio_irq_release(esp32_callback(esp_radio_irq));esp_radio_isr=0;esp_radio_isr_arg=0;esp32_irq_restore(ps);return 0;
}
