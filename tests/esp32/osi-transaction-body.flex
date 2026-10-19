// Same real failure/ownership contract on original and S3 cached targets.
fn ot_check(ready) {return esp32_call32(esp32_external("c_transaction_check"),ready,0,0,0,0,0,0,0);}
fn main() {
    let lower=esp_sdk_heap_min();if esp_sdk_heap_init(lower,esp_sdk_heap_max()-lower) || esp_sdk_task_init() {return 1;}
    esp32_call32(esp32_external("c_transaction_reset"),0,0,0,0,0,0,0,0);let baseline=esp_sdk_heap_free();let remaining=96;
    while remaining<=640 {let held=esp_sdk_malloc(baseline-remaining);let free=esp_sdk_heap_free();
        if !held || esp_radio_os_init()!= -12 || esp_radio_osi || esp_radio_owner || esp_sdk_timer_task || esp_sdk_heap_free()!=free || ot_check(0) {return 2;}
        esp_sdk_free(held);remaining=remaining+544;
    }
    if esp_radio_resources_begin(1) {return 3;}let held=esp_sdk_malloc(baseline-640);let free=esp_sdk_heap_free();
    if !held || esp_radio_os_init()!= -12 || esp_radio_osi || esp_radio_owner!=1 || esp_sdk_timer_task || esp_sdk_heap_free()!=free || ot_check(0) {return 4;}esp_sdk_free(held);
    if esp_radio_resources_end(esp32_callback(esp_radio_irq)) || esp_radio_owner || esp_sdk_heap_free()!=baseline {return 5;}
    if esp_radio_os_init() || !esp_radio_osi || esp_radio_owner!=1 || !esp_sdk_timer_task || !esp_radio_timer_created || ot_check(1) || esp_radio_os_init()!= -16 {return 6;}
    if esp_radio_resources_end(esp32_callback(esp_radio_irq)) || esp_radio_owner || esp_sdk_timer_task || esp_sdk_heap_free()!=baseline || ot_check(1) {return 7;}
    esp_radio_osi=0;esp_uart_write("PASS: OS table scratch/timer failure, borrowed ownership and complete publish/cleanup\r\n");return 0;
}
