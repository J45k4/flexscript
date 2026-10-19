import "esp32s3.flex";
global esp_irq_table=0;
global esp_irq_count=0;
global esp_irq_soft_handler=0;
// CPU0 external level-1 interrupt 1 is shared; callbacks acknowledge their
// device and inspect its pending bit. Handler signature: fn handler(source).
// Reserve table capacity without publishing handlers, routes or enable bits.
// Multi-source adapters preflight ownership first, then reserve under their mask.
fn esp_irq_reserve(additional) {
    if additional<0 || additional>32 {return -22;}let ps=esp32_irq_save();
    if esp_irq_count+additional>32 {esp32_irq_restore(ps);return -12;}
    if additional && !esp_irq_table {esp_irq_table=alloc(32*16);if esp_irq_table<0 {esp_irq_table=0;esp32_irq_restore(ps);return -12;}}
    esp32_irq_restore(ps);return 0;
}
fn esp_irq_attach(source,handler) {
    if source<0 || source>=99 || handler<=0 || (handler>>32) {return -22;}
    let ps=esp32_irq_save();
    let i=0;while i<esp_irq_count && load64(esp_irq_table+i*16)!=source {i=i+1;}
    let needed=0;if i==esp_irq_count {needed=1;}let result=esp_irq_reserve(needed);if result {esp32_irq_restore(ps);return result;}
    store64(esp_irq_table+i*16,source);store64(esp_irq_table+i*16+8,handler);if i==esp_irq_count {esp_irq_count=esp_irq_count+1;}
    esp32_store32(0x600c2000+source*4,1);esp32_irq_mask(esp32_irq_enabled()|2);esp32_irq_restore(ps);return 0;
}
fn esp_irq_detach(source) {
    if source<0 || source>=99 {return -22;}let ps=esp32_irq_save();
    esp32_store32(0x600c2000+source*4,6);let i=0;
    while i<esp_irq_count {if load64(esp_irq_table+i*16)==source {esp_irq_count=esp_irq_count-1;store64(esp_irq_table+i*16,load64(esp_irq_table+esp_irq_count*16));store64(esp_irq_table+i*16+8,load64(esp_irq_table+esp_irq_count*16+8));}else {i=i+1;}}
    esp32_irq_restore(ps);return 0;
}
fn esp_irq_software(handler) {
    if handler<=0 || handler>>32 {return -22;}let ps=esp32_irq_save();let first=!esp_irq_soft_handler;esp_irq_soft_handler=handler;
    // A replacement owns an already-pending event; initial install drops stale state.
    if first {esp32_irq_clear(128);}esp32_irq_mask(esp32_irq_enabled()|128);esp32_irq_restore(ps);return 0;
}
fn esp_irq_enable() {esp32_irq_restore(0);return 0;}
fn esp_irq_dispatch(pending) {
    if (pending&128) {esp32_irq_clear(128);if esp_irq_soft_handler {esp32_call(esp_irq_soft_handler,-1);}}
    if pending&2 {let i=0;while i<esp_irq_count {esp32_call(load64(esp_irq_table+i*16+8),load64(esp_irq_table+i*16));i=i+1;}}
    return 0;
}

fn esp_irq_handler(source) {let i=0;while i<esp_irq_count {if load64(esp_irq_table+i*16)==source {return load64(esp_irq_table+i*16+8);}i=i+1;}return 0;}
