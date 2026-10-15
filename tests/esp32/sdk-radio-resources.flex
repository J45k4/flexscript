import "../../lib/platform/esp32-radio-os.flex";
global resource_irqs=0;
global resource_timer_phase=0;
global resource_key=0;
fn resource_application_irq(source) {if source==14 {resource_irqs=resource_irqs+1;}return 0;}
fn resource_radio_irq(source) {return 0;}
fn resource_timer(a,b,c,d,e,f,g,h) {return 0;}
fn resource_yielding_timer(a,b,c,d,e,f,g,h) {
    esp_sdk_timer_done(resource_key);resource_timer_phase=1;esp_sdk_delay(2);resource_timer_phase=2;return 0;
}
fn resource_child(a,b,c,d,e,f,g,h) {esp_radio_cb_thread_sem(0,0,0,0,0,0,0,0);return 0;}
fn main() {
    if esp_sdk_heap_init(0x3ffc8000,98304) || esp_sdk_task_init() {return 1;}esp_irq_enable();
    let application=esp_sdk_sem_create(1,1);let guard=esp_sdk_malloc(80);let i=0;while i<80 {store8(guard+i,(i*19+3)&255);i=i+1;}let baseline=esp_sdk_heap_free();
    if esp_sdk_heap_release_owner(0)!= -22 || esp_sdk_heap_release_owner(8)!= -22 {return 2;}
    let a=esp_sdk_heap_tag(esp_sdk_malloc(37),1);let b=esp_sdk_heap_tag(esp_sdk_malloc(63),2);if !a || !b {return 3;}store8(a,71);
    let c=esp_sdk_realloc(a,129);if !c || esp_sdk_heap_owner(c)!=1 || load8(c)!=71 || esp_sdk_realloc(c,98305) {return 4;}
    if esp_sdk_heap_release_owner(1)!=1 || esp_sdk_heap_owner(b)!=2 || esp_sdk_heap_release_owner(2)!=1 || esp_sdk_heap_free()!=baseline {return 5;}
    if esp_irq_attach(14,esp32_callback(resource_application_irq)) {return 6;}esp32_store32(0x3ff00104,6);let round=0;
    while round<8 {
        if esp_radio_resources_begin(1+round%2) || esp_radio_resources_begin(1)!= -16 {return 7;}
        if esp_radio_irq_claim(14)!= -16 || esp_radio_irq_claim(0) || esp_irq_attach(0,esp32_callback(resource_radio_irq)) {return 8;}
        esp_radio_isr=esp32_callback32(resource_timer);esp_radio_cb_ints_off(0,0,0,0,0,0,0,0);if !(esp32_irq_enabled()&2) || esp32_load32(0x3ff00104)!=6 {return 9;}esp_radio_cb_ints_on(0,0,0,0,0,0,0,0);
        if !esp_radio_cb_thread_sem(0,0,0,0,0,0,0,0) || !esp_radio_cb_mutex(0,0,0,0,0,0,0,0) || !esp_radio_cb_queue(3,7,0,0,0,0,0,0) {return 10;}
        let task=esp_radio_task_owned(esp_sdk_task_create(esp32_callback32(resource_child),0,4096,3));if !task || esp_radio_resources_ready()!= -16 || esp_radio_resources_end(esp32_callback(resource_radio_irq))!= -16 || !esp_radio_owner || esp_irq_count!=2 {return 11;}while load64(task+544)!=2 {esp_sdk_yield();}
        let own_key=alloc(8);if esp_radio_cb_timer_setfn(own_key,esp32_callback32(resource_timer),0,0,0,0,0,0) {return 12;}
        if esp_sdk_timer_init() {return 13;}esp_radio_timer_created=1;
        let app_key=0;if round&1 {app_key=alloc(8);if esp_sdk_timer_setfn(app_key,esp32_callback32(resource_timer),0) || esp_radio_cb_timer_setfn(app_key,esp32_callback32(resource_timer),0,0,0,0,0,0)!= -16 {return 14;}}
        if esp_radio_resources_end(esp32_callback(resource_radio_irq)) || esp_radio_owner || load64(esp_sdk_tasks+568) || esp_irq_count!=1 || esp_irq_handler(14)!=esp32_callback(resource_application_irq) || esp32_load32(0x3ff00104)!=6 || !(esp32_irq_enabled()&2) {return 15;}
        if app_key {if !esp_sdk_timer_task || !esp_sdk_timer_find(app_key) || esp_sdk_timer_deinit()!= -16 {return 16;}esp_sdk_timer_done(app_key);if esp_sdk_timer_deinit() {return 17;}}
        if esp_sdk_heap_free()!=baseline || load64(esp_sdk_tasks+536)!=esp_sdk_tasks || !esp_sdk_sem_take(application,0) || !esp_sdk_sem_give(application) {return 18;}
        i=0;while i<80 {if load8(guard+i)!=((i*19+3)&255) {return 19;}i=i+1;}esp_irq_dispatch(2);round=round+1;
    }
    if resource_irqs!=8 || esp_sdk_timer_init() {return 20;}resource_key=alloc(8);
    if esp_sdk_timer_setfn(resource_key,esp32_callback32(resource_yielding_timer),0) || esp_sdk_timer_arm(resource_key,1,0) {return 21;}
    while !resource_timer_phase {esp_sdk_yield();}if resource_timer_phase!=1 || !esp_sdk_timer_active || esp_sdk_timers || esp_sdk_timer_deinit()!= -16 {return 22;}
    while resource_timer_phase!=2 || esp_sdk_timer_active {esp_sdk_yield();}if esp_sdk_timer_deinit() || esp_sdk_heap_free()!=baseline {return 23;}
    // Last-radio teardown must also remove its CPU interrupt bits when no
    // shared external user remains, while preserving unrelated enable bits.
    esp_irq_detach(14);esp32_irq_mask(4);let route=esp32_load32(0x3ff00104+6*4);
    if esp_radio_resources_begin(2) || esp_radio_irq_claim(6) || esp_irq_attach(6,esp32_callback(resource_radio_irq)) {return 24;}
    esp_radio_soft_owned=1;if esp_irq_software(esp32_callback(resource_radio_irq)) || esp_radio_resources_end(esp32_callback(resource_radio_irq)) || esp_irq_count || esp_irq_soft_handler || esp32_irq_enabled()!=4 || esp32_load32(0x3ff00104+6*4)!=route || esp_sdk_heap_free()!=baseline {return 25;}esp32_irq_mask(0);
    esp_uart_write("PASS: resource domains, realloc, eight radio cleanup cycles, shared IRQ/timers and yielding callback guards\r\n");esp_uart_flush();return 0;
}
