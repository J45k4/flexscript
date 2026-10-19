// ESP32-S3 software timers share the same implementation as original ESP32.
import "../../lib/platform/esp32s3.flex";
import "../../lib/platform/esp32s3-sdk-sync.flex";
import "../../lib/platform/esp32s3-sdk-timer.flex";
global timer_count=0;
global timer_key=0;
global timer_sem=0;
global timer_bad_context=0;
fn timer_cb(a,b,c,d,e,f,g,h) {
    if a!=42 || esp_sdk_current!=esp_sdk_timer_task || esp32_load32(esp32_state()+16) {timer_bad_context=1;}
    timer_count=timer_count+1;
    if timer_count==3 {esp_sdk_timer_done(timer_key);esp_sdk_sem_give(timer_sem);}return 0;
}
fn timer_once(a,b,c,d,e,f,g,h) {timer_cb(a,b,c,d,e,f,g,h);esp_sdk_sem_give(timer_sem);return 0;}
fn main() {
    if esp_sdk_heap_init(0x3fcc6000,40960) || esp_sdk_task_init() || esp_sdk_timer_init() {return 1;}esp32_irq_restore(0);
    timer_key=esp_sdk_calloc(1,20);timer_sem=esp_sdk_sem_create(1,0);let before=esp_sdk_heap_free();
    if esp_sdk_timer_setfn(timer_key,esp32_callback32(timer_cb),42) || esp_sdk_timer_arm(timer_key,1000,1) {return 2;}
    if !esp_sdk_sem_take(timer_sem,100) || timer_count!=3 || timer_bad_context || esp_sdk_heap_free()!=before {return 3;}
    // Rearming replaces the deadline; disarming suppresses it; deleting is safe twice.
    if esp_sdk_timer_setfn(timer_key,esp32_callback32(timer_cb),42) || esp_sdk_timer_arm(timer_key,1000,0) {return 4;}
    esp_sdk_timer_disarm(timer_key);esp_sdk_delay(3);if timer_count!=3 {return 5;}
    esp_sdk_timer_done(timer_key);esp_sdk_timer_done(timer_key);if esp_sdk_heap_free()!=before {return 6;}
    timer_count=0;
    if esp_sdk_timer_setfn(timer_key,esp32_callback32(timer_once),42) || esp_sdk_timer_arm(timer_key,0,0) {return 7;}
    if !esp_sdk_sem_take(timer_sem,100) || timer_count!=1 || timer_bad_context {return 8;}esp_sdk_timer_done(timer_key);if esp_sdk_heap_free()!=before {return 9;}
    esp_uart_write("PASS: SDK timers, callback deletion, cancellation and task context\r\n");return 0;
}
