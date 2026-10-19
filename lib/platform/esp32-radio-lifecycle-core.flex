import "esp32-sdk-timer-core.flex";
import "esp32-analog-state.flex";
// One standalone radio image owns one domain: 1=Wi-Fi, 2=Bluetooth. Explicit
// OSI allocations are tagged; ordinary application/TLS/IP allocations are not.
// Simultaneous radios require the separate coexistence implementation.
// Domain/list transitions are masked as one operation, including nested heap
// and timer-service calls. Vendor init/deinit happens outside this mask.
global esp_radio_irq_routes=0;
global esp_radio_irq_before=0;
global esp_radio_timer_created=0;
global esp_radio_soft_owned=0;
fn esp_radio_owned(pointer) {return esp_sdk_heap_tag(pointer,esp_radio_owner);}
fn esp_radio_resources_begin(owner) {let ps=esp32_irq_save();
    if esp_radio_owner || esp_adc_busy || esp_radio_base_active || esp_radio_regi2c_active || esp_radio_pmu_active || !esp_sdk_current || esp32_load32(esp32_state()+16) {esp32_irq_restore(ps);return -16;}if owner!=1 && owner!=2 {esp32_irq_restore(ps);return -22;}
    if !esp_radio_irq_routes {esp_radio_irq_routes=alloc(esp_radio_source_count()*16);if esp_radio_irq_routes<=0 {esp_radio_irq_routes=0;esp32_irq_restore(ps);return -12;}}
    let i=0;while i<esp_radio_source_count() {store64(esp_radio_irq_routes+i*16,0);i=i+1;}
    esp_radio_irq_before=esp32_irq_enabled();esp_radio_soft_owned=0;esp_radio_timer_created=0;esp_radio_owner=owner;esp32_irq_restore(ps);return 0;
}
// Check a complete adapter registration before changing any claimed source.
fn esp_radio_irq_can_claim(source,handler) {
    let ps=esp32_irq_save();if !esp_radio_owner || !esp_radio_irq_routes || source<0 || source>=esp_radio_source_count() {esp32_irq_restore(ps);return -22;}
    let existing=esp_irq_handler(source);if existing && (!load64(esp_radio_irq_routes+source*16) || existing!=handler) {esp32_irq_restore(ps);return -16;}
    esp32_irq_restore(ps);return 0;
}
fn esp_radio_irq_claim(source) {let ps=esp32_irq_save();
    if !esp_radio_owner || source<0 || source>=esp_radio_source_count() {esp32_irq_restore(ps);return -22;}let p=esp_radio_irq_routes+source*16;
    if !load64(p) {if esp_irq_handler(source) {esp32_irq_restore(ps);return -16;}store64(p+8,esp32_load32(esp_radio_route(source)));store64(p,1);}esp32_irq_restore(ps);return 0;
}
fn esp_radio_irq_release(handler) {
    let ps=esp32_irq_save();let source=0;while source<esp_radio_source_count() {let p=esp_radio_irq_routes+source*16;
        if load64(p) {if esp_irq_handler(source)==handler {esp_irq_detach(source);}if !esp_irq_handler(source) {esp32_store32(esp_radio_route(source),load64(p+8));}store64(p,0);}source=source+1;
    }
    let mask=esp32_irq_enabled();if !esp_irq_count {mask=(mask&~2)|(esp_radio_irq_before&2);}
    if esp_radio_soft_owned && esp_irq_soft_handler==handler {esp_irq_soft_handler=0;esp32_irq_clear(128);mask=(mask&~128)|(esp_radio_irq_before&128);}
    esp32_irq_mask(mask);esp_radio_soft_owned=0;esp32_irq_restore(ps);return 0;
}
fn esp_radio_task_owned(task) {if task {store64(task+584,esp_radio_owner);}return task;}
fn esp_radio_resources_ready() {let ps=esp32_irq_save();
    if esp_radio_base_active || esp_radio_regi2c_active || esp_radio_pmu_active {esp32_irq_restore(ps);return -16;}if !esp_radio_owner {esp32_irq_restore(ps);return 0;}if !esp_sdk_current || esp32_load32(esp32_state()+16) || esp_sdk_timer_active || load64(esp_sdk_current+584)==esp_radio_owner {esp32_irq_restore(ps);return -16;}
    let t=esp_sdk_tasks;while t {if load64(t+584)==esp_radio_owner && load64(t+544)!=2 {esp32_irq_restore(ps);return -16;}t=load64(t+536);if t==esp_sdk_tasks {t=0;}}esp32_irq_restore(ps);return 0;
}
fn esp_radio_resources_end(handler) {let ps=esp32_irq_save();
    if !esp_radio_owner {esp32_irq_restore(ps);return 0;}let r=esp_radio_resources_ready();if r {esp32_irq_restore(ps);return r;}
    // Vendor deinit has completed and all its tasks have exited. Remove only
    // domain-owned timer nodes, then unlink/reap TCBs before freeing objects.
    let t=esp_sdk_timers;while t {let next=load64(t);if esp_sdk_heap_owner(t)==esp_radio_owner {esp_sdk_timer_done(load64(t+8));}t=next;}
    t=esp_sdk_tasks;while t {let next=load64(t+536);if load64(t+584)==esp_radio_owner {r=esp_sdk_task_reap(t);if r {esp32_irq_restore(ps);return r;}}t=next;if t==esp_sdk_tasks {t=0;}}
    t=esp_sdk_tasks;while t {let sem=load64(t+568);if sem && esp_sdk_heap_owner(sem)==esp_radio_owner {store64(t+568,0);}t=load64(t+536);if t==esp_sdk_tasks {t=0;}}
    esp_radio_irq_release(handler);r=esp_sdk_heap_release_owner(esp_radio_owner);if r<0 {esp32_irq_restore(ps);return r;}
    if esp_radio_timer_created && !esp_sdk_timers {r=esp_sdk_timer_deinit();if r {esp32_irq_restore(ps);return r;}}
    esp_radio_timer_created=0;esp_radio_owner=0;esp32_irq_restore(ps);return 0;
}
