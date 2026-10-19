import "../../lib/platform/esp32c3-xip.flex";
import "../../lib/platform/esp32c3-radio-os.flex";
global so_checks=0;
global so_error=0;
global so_hook=0;
global so_isr_result=0;
fn so_check(ok) {so_checks=so_checks+1;if !ok {esp_uart_write("RISC-V OSI FAIL ");esp_uart_hex(so_checks);esp_uart_write("\r\n");so_error=1;}return ok;}
fn so_call(address,arg) {return esp32_call32(address,arg,0,0,0,0,0,0,0);}
fn so_irq(source) {so_isr_result=esp_radio_os_init();return 0;}
fn so_event(id) {if id==42 && esp_radio_event_size==8 && esp32_load32(esp_radio_event_data)==0x12345678 && esp32_load32(esp_radio_event_data+4)==0x87654321 {so_hook=so_hook+1;}return 0;}
fn main() {
    let begin=esp_sdk_heap_min();if esp_sdk_heap_init(begin,esp_sdk_heap_max()-begin) || esp_libc_stdio_init() || esp_libc_rom_init() || esp_sdk_task_init() {return 1;}
    so_call(esp32_external("c_rv_osi_reset"),0);let baseline=esp_sdk_heap_free();let mask=esp32_irq_enabled();
    if !so_check(esp_radio_os_size()==(480+(rv_hal_chip==13)*28) && esp_radio_nvs_offset()==268) {return 2;}
    let i=0;while i<esp_radio_os_size()/4 {if !so_check(so_call(esp32_external("c_rv_osi_offset"),i)==i*4) {return 3;}i=i+1;}
    if esp_irq_software(esp32_callback(so_irq)) {return 4;}esp32_irq_raise(128);esp_sdk_task_unmask();let start=esp32_cycles();while !so_isr_result && ((esp32_cycles()-start)&4294967295)<1000000 {}esp32_irq_save();esp_irq_soft_handler=0;esp32_irq_clear(128);esp32_irq_mask(mask);
    if !so_check(so_isr_result== -16 && !esp_radio_osi && !esp_radio_owner && esp_sdk_heap_free()==baseline && !so_call(esp32_external("c_rv_osi_guard_check"),1)) {return 5;}
    // Scratch allocation failure, then timer TCB failure after table preparation.
    let remaining=96;while remaining<=640 {
        let held=esp_sdk_malloc(baseline-remaining);if !held {return 6;}let free=esp_sdk_heap_free();
        if !so_check(esp_radio_os_init()== -12 && !esp_radio_osi && !esp_radio_owner && !esp_sdk_timer_task && !esp_radio_timer_created && esp_sdk_heap_free()==free && !so_call(esp32_external("c_rv_osi_guard_check"),1)) {return 7;}
        esp_sdk_free(held);remaining=remaining+544;
    }
    esp_radio_regi2c_active=1;
    if !so_check(esp_radio_resources_begin(1)== -16 && !esp_radio_owner && esp_sdk_heap_free()==baseline) {return 18;}
    esp_radio_regi2c_active=0;
    if !so_check(!esp_radio_resources_begin(1)) {return 8;}
    esp_radio_regi2c_active=1;
    if !so_check(esp_radio_resources_ready()== -16 && esp_radio_resources_end(esp32_iram_callback(esp_radio_irq))== -16 && esp_radio_owner==1 && esp_sdk_heap_free()==baseline) {return 19;}
    esp_radio_regi2c_active=0;let held=esp_sdk_malloc(baseline-640);let free=esp_sdk_heap_free();
    if !so_check(held && esp_radio_os_init()== -12 && !esp_radio_osi && esp_radio_owner==1 && !esp_sdk_timer_task && esp_sdk_heap_free()==free && !so_call(esp32_external("c_rv_osi_guard_check"),1)) {return 9;}esp_sdk_free(held);
    if !so_check(!esp_radio_resources_end(esp32_iram_callback(esp_radio_irq)) && !esp_radio_owner && esp_sdk_heap_free()==baseline) {return 10;}
    let nvs=alloc(48);
    // Distinct real C return values prove all twelve shifted NVS slots.
    esp32_store32(nvs,esp32_external("c_rv_osi_nvs_0"));esp32_store32(nvs+4,esp32_external("c_rv_osi_nvs_1"));esp32_store32(nvs+8,esp32_external("c_rv_osi_nvs_2"));esp32_store32(nvs+12,esp32_external("c_rv_osi_nvs_3"));esp32_store32(nvs+16,esp32_external("c_rv_osi_nvs_4"));esp32_store32(nvs+20,esp32_external("c_rv_osi_nvs_5"));esp32_store32(nvs+24,esp32_external("c_rv_osi_nvs_6"));esp32_store32(nvs+28,esp32_external("c_rv_osi_nvs_7"));esp32_store32(nvs+32,esp32_external("c_rv_osi_nvs_8"));esp32_store32(nvs+36,esp32_external("c_rv_osi_nvs_9"));esp32_store32(nvs+40,esp32_external("c_rv_osi_nvs_10"));esp32_store32(nvs+44,esp32_external("c_rv_osi_nvs_11"));esp_radio_nvs_table=nvs;
    if !so_check(!esp_radio_os_init() && esp_radio_osi==esp32_external("g_wifi_osi_funcs") && esp_radio_owner==1 && esp_sdk_timer_task && esp_radio_timer_created && !so_call(esp32_external("c_rv_osi_guard_check"),0) && !so_call(esp32_external("c_rv_osi_nvs_check"),0)) {return 11;}
    if !so_check(esp_radio_os_init()== -16 && !so_call(esp32_external("c_rv_osi_guard_check"),0)) {return 12;}
    esp_radio_event_hook=esp32_callback(so_event);let cal_address=0x60008054;if rv_hal_chip==13{cal_address=0x600b1004;}let saved_cal=esp32_load32(cal_address);esp32_store32(cal_address,0x12345680);if esp32_load32(cal_address)!=0x12345680 {return 17;}esp_sdk_task_unmask();let code=so_call(esp32_external("c_rv_osi_exercise"),esp_sdk_current);esp32_irq_save();esp32_store32(cal_address,saved_cal);
    if !so_check(!code && so_hook==1 && esp_radio_events==1 && esp_radio_last_event==42 && !esp_radio_event_data && !esp_radio_event_size) {esp_uart_write("C peer code=");esp_uart_hex(code);return 13;}
    if !so_check(!esp_radio_resources_end(esp32_iram_callback(esp_radio_irq)) && !esp_radio_owner && !esp_sdk_timer_task && !load64(esp_sdk_current+568) && esp_sdk_heap_free()==baseline && !so_call(esp32_external("c_rv_osi_guard_check"),0)) {return 14;}
    esp_radio_osi=0;esp_radio_nvs_table=0;esp_radio_event_hook=0;esp_uart_write("PASS: RISC-V vendor v9 offsets, typed C callbacks/NVS, transactional allocation failure and cleanup checks=");esp_uart_hex(so_checks);esp_uart_write("\r\n");return 0;
}
