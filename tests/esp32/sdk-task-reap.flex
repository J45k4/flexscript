import "../../lib/platform/esp32-radio-os.flex";
global reap_child_error=0;
global reap_child_sem=0;
fn reap_child(a,b,c,d,e,f,g,h) {
    let first=esp_radio_cb_thread_sem(0,0,0,0,0,0,0,0);let second=esp_radio_cb_thread_sem(0,0,0,0,0,0,0,0);reap_child_sem=first;
    if !first || first!=second || !esp_sdk_sem_give(first) || !esp_sdk_sem_take(first,0) {reap_child_error=1;}return 0;
}
fn main() {
    if esp_sdk_heap_init(0x3ffc8000,98304) || esp_sdk_task_init() {return 1;}
    let application=esp_sdk_sem_create(1,1);let guard=esp_sdk_malloc(80);if !application || !guard {return 2;}let i=0;while i<80 {store8(guard+i,(i*29+7)&255);i=i+1;}let baseline=esp_sdk_heap_free();let round=0;
    while round<8 {reap_child_error=0;reap_child_sem=0;let task=esp_sdk_task_create(esp32_callback32(reap_child),0,4096,3);if !task {return 3;}while load64(task+544)!=2 {esp_sdk_yield();}
        if reap_child_error || !reap_child_sem || load64(task+568)!=reap_child_sem {return 4;}if esp_sdk_task_reap(task) {return 5;}
        if esp_sdk_heap_free()!=baseline {esp_uart_write("TASK REAP LEAK ");esp_uart_hex(baseline-esp_sdk_heap_free());esp_uart_write("\r\n");return 6;}
        if load64(esp_sdk_tasks+536)!=esp_sdk_tasks || !esp_sdk_sem_take(application,0) || !esp_sdk_sem_give(application) {return 7;}i=0;while i<80 {if load8(guard+i)!=((i*29+7)&255) {return 8;}i=i+1;}round=round+1;
    }esp_uart_write("PASS: eight task/thread-sem reap cycles, exact heap recovery and application guards\r\n");esp_uart_flush();return 0;
}
