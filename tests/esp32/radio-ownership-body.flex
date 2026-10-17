// Identical radio-domain tests execute against the original and S3 adapters.
global ro_calls=0;
global ro_task_calls=0;
global ro_checks=0;
fn ro_check(ok,code) {ro_checks=ro_checks+1;if !ok {esp_uart_write("OWNERSHIP FAIL ");esp_uart_hex(code);esp_uart_write("\r\n");}return ok;}
fn ro_app(source) {ro_calls=ro_calls+1;return 0;}
fn ro_radio(source) {return 0;}
fn ro_task(a,b,c,d,e,f,g,h) {ro_task_calls=ro_task_calls+1;return 0;}
fn ro_timer(a,b,c,d,e,f,g,h) {return 0;}
fn main() {
    let s3=esp32_state()==0x3fcc0000;let arena=0x3ffc8000;let bytes=98304;let app_source=14;let count=69;let matrix=0x3ff00104;
    if s3 {arena=0x3fcc6000;bytes=40960;app_source=50;count=99;matrix=0x600c2000;}
    if esp_sdk_heap_init(arena,bytes) || esp_sdk_task_init() {return 1;}esp_irq_enable();
    let free=esp_sdk_heap_free();let own=esp32_callback(ro_radio);let app=esp32_callback(ro_app);let last=count-1;
    if !ro_check(esp_radio_source_count()==count && esp_radio_route(last)==matrix+last*4,1) {return 1;}
    if !ro_check(esp_irq_reserve(-1)== -22 && esp_irq_reserve(33)== -22 && !esp_irq_reserve(0) && !esp_irq_table && !esp_irq_count,2) {return 2;}
    if !ro_check(esp_radio_resources_begin(0)== -22 && esp_radio_resources_begin(3)== -22 && !esp_radio_owner,3) {return 3;}
    esp_adc_busy=1;if !ro_check(esp_radio_resources_begin(1)== -16 && !esp_radio_owner,4) {return 4;}esp_adc_busy=0;
    if !ro_check(!esp_irq_attach(app_source,app),5) {return 5;}
    let before_mask=esp32_irq_enabled();let round=0;
    while round<8 {
        let owner=1+round%2;
        if !ro_check(!esp_radio_resources_begin(owner) && esp_radio_owner==owner && esp_radio_resources_begin(owner)== -16,6) {return 6;}
        if !ro_check(esp_radio_irq_claim(-1)== -22 && esp_radio_irq_claim(count)== -22 && esp_radio_irq_can_claim(count,own)== -22 && esp_radio_irq_claim(app_source)== -16 && esp_radio_irq_can_claim(app_source,own)== -16,7) {return 7;}
        let ps=esp32_irq_save();esp32_store32(matrix,3+round%3);esp32_store32(matrix+8,9+round%3);esp32_store32(matrix+last*4,13+round%3);esp32_irq_restore(ps);
        let route0=esp32_load32(matrix);let route2=esp32_load32(matrix+8);let route_last=esp32_load32(matrix+last*4);
        if !ro_check(!esp_radio_irq_can_claim(0,own) && !esp_radio_irq_can_claim(2,own) && !esp_irq_reserve(3) && !esp_radio_irq_claim(0) && !esp_radio_irq_claim(2) && !esp_radio_irq_claim(last),8) {return 8;}
        if !ro_check(!esp_irq_attach(0,own) && !esp_irq_attach(2,own) && !esp_irq_attach(last,own) && esp_irq_count==4 && esp32_load32(matrix)==1 && esp32_load32(matrix+8)==1 && esp32_load32(matrix+last*4)==1,9) {return 9;}
        let tagged=esp_radio_owned(esp_sdk_malloc(48));let sem=esp_radio_owned(esp_sdk_sem_create(1,1));if !tagged || !sem {return 10;}store64(esp_sdk_current+568,sem);
        let task=esp_radio_task_owned(esp_sdk_task_create(esp32_callback32(ro_task),0,4096,3));if !task {return 11;}
        if !ro_check(esp_radio_resources_ready()== -16 && esp_radio_resources_end(own)== -16 && esp_radio_owner==owner && esp_irq_count==4,12) {return 12;}
        while load64(task+544)!=2 {esp_sdk_yield();}
        if !ro_check(!esp_sdk_timer_init(),13) {return 13;}esp_radio_timer_created=1;
        let key=alloc(8);let app_key=alloc(8);if esp_sdk_timer_setfn(key,esp32_callback32(ro_timer),0) || esp_sdk_timer_setfn(app_key,esp32_callback32(ro_timer),0) {return 14;}
        esp_radio_owned(esp_sdk_timer_find(key));
        if !ro_check(!esp_radio_resources_end(own) && !esp_radio_owner && !load64(esp_sdk_current+568) && esp_sdk_heap_owner(tagged)== -22 && esp_irq_count==1 && esp_irq_handler(app_source)==app,15) {return 15;}
        if !ro_check(esp32_load32(matrix)==route0 && esp32_load32(matrix+8)==route2 && esp32_load32(matrix+last*4)==route_last && esp32_irq_enabled()==before_mask,16) {return 16;}
        if !ro_check(!esp_sdk_timer_find(key) && esp_sdk_timer_find(app_key) && esp_sdk_timer_task && esp_sdk_timer_deinit()== -16,17) {return 17;}
        esp_sdk_timer_done(app_key);if !ro_check(!esp_sdk_timer_deinit() && esp_sdk_heap_free()==free && load64(esp_sdk_tasks+536)==esp_sdk_tasks,18) {return 18;}
        esp_irq_dispatch(2);round=round+1;
    }
    if !ro_check(ro_calls==8 && ro_task_calls==8 && !esp_irq_detach(app_source),19) {return 19;}
    // Reserving a two-source registration at31 entries must leave every route,
    // handler and enable bit untouched. Replacing an existing handler still fits.
    let i=3;while i<34 {if esp_irq_attach(i,app) {return 20;}i=i+1;}
    let old0=esp32_load32(matrix);let old2=esp32_load32(matrix+8);let mask=esp32_irq_enabled();let heap=esp32_load32(esp32_state());
    if !ro_check(esp_irq_reserve(2)== -12 && esp_irq_count==31 && esp32_irq_enabled()==mask && esp32_load32(matrix)==old0 && esp32_load32(matrix+8)==old2 && esp32_load32(esp32_state())==heap && !esp_irq_handler(0) && !esp_irq_handler(2),21) {return 21;}
    if !ro_check(!esp_irq_attach(3,own) && !esp_irq_reserve(1) && !esp_irq_attach(2,own) && esp_irq_count==32 && esp_irq_attach(0,own)== -12 && !esp_irq_handler(0) && esp32_load32(matrix)==old0,22) {return 22;}
    i=2;while i<34 {esp_irq_detach(i);i=i+1;}
    esp32_irq_mask(4);let route=esp32_load32(matrix);if esp_radio_resources_begin(2) || esp_radio_irq_claim(0) || esp_irq_attach(0,own) || esp_irq_software(own) {return 23;}esp_radio_soft_owned=1;
    if !ro_check(!esp_radio_resources_end(own) && !esp_radio_owner && !esp_irq_count && !esp_irq_soft_handler && esp32_irq_enabled()==4 && esp32_load32(matrix)==route && esp_sdk_heap_free()==free,24) {return 24;}
    esp32_irq_mask(0);esp_uart_write("PASS: chip-specific radio ownership, MAC/power/end-source IRQs, atomic capacity and8 complete cleanup cycles; checks=");esp_uart_hex(ro_checks);esp_uart_write("\r\n");esp_uart_flush();return 0;
}
