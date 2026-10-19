// CPU0, masked non-nested callbacks. Source owners acknowledge their peripheral.
// Legacy INTC on C3; PLIC on C6. See pinned ESP-IDF v5.5.1 interrupt LL.
global esp_irq_table=0;
global esp_irq_count=0;
global esp_irq_soft_handler=0;
fn esp_irq_matrix() {if !esp_riscv_ready() {return 0;}if rv_hal_chip==5 {return 0x600c2000;}return 0x60010000;}
fn esp_irq_sources() {if !esp_riscv_ready() {return 0;}if rv_hal_chip==5 {return 62;}return 77;}
fn esp_irq_soft_source() {if rv_hal_chip==5 {return 50;}return 22;}
fn esp_irq_priority(line) {if rv_hal_chip==5 {return 0x600c2114+line*4;}return 0x20001010+line*4;}

fn esp_irq_reserve(additional) {
    if !esp_irq_matrix() {return -95;}if additional<0 || additional>32 {return -22;}let ps=esp32_irq_save();
    if esp_irq_count+additional>32 {esp32_irq_restore(ps);return -12;}
    if additional && !esp_irq_table {if esp32_load32(esp32_state()+16) {esp32_irq_restore(ps);return -16;}esp_irq_table=alloc(512);if esp_irq_table<=0 {esp_irq_table=0;esp32_irq_restore(ps);return -12;}}
    esp32_irq_restore(ps);return 0;
}
fn esp_irq_handler(source) {let i=0;while i<esp_irq_count {if load64(esp_irq_table+i*16)==source {return load64(esp_irq_table+i*16+8);}i=i+1;}return 0;}
fn esp_irq_attach(source,handler) {
    if !esp_irq_matrix() {return -95;}if source<0 || source>=esp_irq_sources() || handler<=0 || handler>>32 {return -22;}
    let ps=esp32_irq_save();if source==esp_irq_soft_source() && esp_irq_soft_handler {esp32_irq_restore(ps);return -16;}
    let i=0;while i<esp_irq_count && load64(esp_irq_table+i*16)!=source {i=i+1;}
    let needed=0;if i==esp_irq_count {needed=1;}let result=esp_irq_reserve(needed);if result {esp32_irq_restore(ps);return result;}
    store64(esp_irq_table+i*16,source);store64(esp_irq_table+i*16+8,handler);if needed {esp_irq_count=esp_irq_count+1;}
    esp32_store32(esp_irq_priority(1),1);esp32_store32(esp_irq_matrix()+source*4,1);esp32_irq_mask(esp32_irq_enabled()|2);esp32_irq_restore(ps);return 0;
}
fn esp_irq_detach(source) {
    if !esp_irq_matrix() {return -95;}if source<0 || source>=esp_irq_sources() {return -22;}let ps=esp32_irq_save();
    let i=0;while i<esp_irq_count && load64(esp_irq_table+i*16)!=source {i=i+1;}
    if i<esp_irq_count {esp32_store32(esp_irq_matrix()+source*4,0);esp_irq_count=esp_irq_count-1;store64(esp_irq_table+i*16,load64(esp_irq_table+esp_irq_count*16));store64(esp_irq_table+i*16+8,load64(esp_irq_table+esp_irq_count*16+8));if !esp_irq_count {esp32_irq_mask(esp32_irq_enabled()&~2);}}
    esp32_irq_restore(ps);return 0;
}
fn esp_irq_software(handler) {
    if !esp_irq_matrix() {return -95;}if handler<=0 || handler>>32 {return -22;}let ps=esp32_irq_save();
    if esp_irq_handler(esp_irq_soft_source()) {esp32_irq_restore(ps);return -16;}let first=!esp_irq_soft_handler;esp_irq_soft_handler=handler;
    if first {esp32_irq_clear(128);}esp32_store32(esp_irq_priority(7),1);esp32_store32(esp_irq_matrix()+esp_irq_soft_source()*4,7);esp32_irq_mask(esp32_irq_enabled()|128);esp32_irq_restore(ps);return 0;
}
fn esp_irq_enable() {let ps=esp32_irq_save();esp32_irq_restore(ps|8);return 0;}
fn esp_irq_dispatch(pending) {
    if pending&128 {esp32_irq_clear(128);if esp_irq_soft_handler {esp32_call(esp_irq_soft_handler,-1);}}
    if pending&2 {let i=0;let calls=0;while i<esp_irq_count && calls<32 {let source=load64(esp_irq_table+i*16);esp32_call(load64(esp_irq_table+i*16+8),source);calls=calls+1;if i<esp_irq_count && load64(esp_irq_table+i*16)==source {i=i+1;}}}return 0;
}
