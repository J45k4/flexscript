import "esp32.flex";
global esp_irq_table=0;
global esp_irq_count=0;
global esp_irq_soft_handler=0;
// CPU0 external level-1 interrupt 1 is shared; callbacks acknowledge their
// device and inspect its pending bit. Handler signature: fn handler(source).
fn esp_irq_attach(source,handler) {
    if source<0 || source>=69 || handler<=0 || (handler>>32) {return -22;}
    let ps=esp32_irq_save();
    if !esp_irq_table {esp_irq_table=alloc(32*16);if esp_irq_table<0 {esp_irq_table=0;esp32_irq_restore(ps);return -12;}}
    let i=0;while i<esp_irq_count && load64(esp_irq_table+i*16)!=source {i=i+1;}
    if i==32 {esp32_irq_restore(ps);return -12;}
    store64(esp_irq_table+i*16,source);store64(esp_irq_table+i*16+8,handler);if i==esp_irq_count {esp_irq_count=esp_irq_count+1;}
    esp32_store32(0x3ff00104+source*4,1);esp32_irq_mask(esp32_irq_enabled()|2);esp32_irq_restore(ps);return 0;
}
fn esp_irq_detach(source) {
    if source<0 || source>=69 {return -22;}let ps=esp32_irq_save();
    esp32_store32(0x3ff00104+source*4,6);let i=0;
    while i<esp_irq_count {if load64(esp_irq_table+i*16)==source {esp_irq_count=esp_irq_count-1;store64(esp_irq_table+i*16,load64(esp_irq_table+esp_irq_count*16));store64(esp_irq_table+i*16+8,load64(esp_irq_table+esp_irq_count*16+8));}else {i=i+1;}}
    esp32_irq_restore(ps);return 0;
}
fn esp_irq_software(handler) {
    if handler<=0 || handler>>32 {return -22;}let ps=esp32_irq_save();esp_irq_soft_handler=handler;
    esp32_irq_clear(128);esp32_irq_mask(esp32_irq_enabled()|128);esp32_irq_restore(ps);return 0;
}
fn esp_irq_enable() {esp32_irq_restore(0);return 0;}
fn esp_irq_dispatch(pending) {
    if (pending&128) {esp32_irq_clear(128);if esp_irq_soft_handler {esp32_call(esp_irq_soft_handler,-1);}}
    if pending&2 {let i=0;while i<esp_irq_count {esp32_call(load64(esp_irq_table+i*16+8),load64(esp_irq_table+i*16));i=i+1;}}
    return 0;
}

fn esp_irq_handler(source) {let i=0;while i<esp_irq_count {if load64(esp_irq_table+i*16)==source {return load64(esp_irq_table+i*16+8);}i=i+1;}return 0;}
