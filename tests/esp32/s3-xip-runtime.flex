import "../../lib/platform/esp32s3-xip.flex";
// ESP32-S3 RAM counterpart of the complete cooperative runtime fixture.
import "../../lib/platform/esp32s3.flex";
import "../../lib/platform/esp32s3-sdk-sync.flex";
import "sdk-heap-churn.flex";
global sdk_stage=0;
global sdk_queue=0;
global sdk_sem=0;
global sdk_event=0;
fn c_task(a,b,c,d,e,f,g,h) {if a==42 {sdk_stage=1;esp_sdk_delay(2);sdk_stage=2;}return 0;}
fn producer(a,b,c,d,e,f,g,h) {let word=esp_sdk_malloc(8);store64(word,914);esp_sdk_delay(2);esp_sdk_queue_op(sdk_queue,word,100,1);esp_sdk_sem_give(sdk_sem);esp_sdk_event_set(sdk_event,7);esp_sdk_free(word);return 0;}
fn main() {
    esp_uart_write("START: SDK runtime\r\n");if esp_sdk_heap_init(0x3fcb2000,122880) {return 1;}let before=esp_sdk_heap_free();let heap_check=sh_churn();if heap_check {return 100+heap_check;}
    let a=esp_sdk_malloc(33);let b=esp_sdk_malloc(2048);if !a || !b || (a&15) || (b&15) {return 2;}
    store8(a,29);let c=esp_sdk_realloc(a,4096);if !c || load8(c)!=29 {return 3;}if esp_sdk_realloc(c,122880) || load8(c)!=29 {return 4;}
    if esp_sdk_free(c) || esp_sdk_free(b) || esp_sdk_heap_free()!=before || esp_sdk_free(c)!=-22 {return 5;}
    let all=esp_sdk_calloc(1,before-16);if !all || esp_sdk_malloc(16) || load8(all+before-17) {return 6;}esp_sdk_free(all);
    if esp_sdk_task_init() {return 7;}esp32_irq_restore(0);let free=esp_sdk_heap_free();let task=esp_sdk_task_create(esp32_callback32(c_task),42,8192,1);if !task {return 8;}
    while sdk_stage!=2 || load64(task+544)!=2 {esp_sdk_yield();}if esp_sdk_task_reap(task) || esp_sdk_heap_free()!=free {return 9;}
    let sem=esp_sdk_sem_create(2,1);if !esp_sdk_sem_take(sem,0) || esp_sdk_sem_take(sem,1) || !esp_sdk_sem_give(sem) || !esp_sdk_sem_give(sem) || esp_sdk_sem_give(sem) {return 10;}esp_sdk_free(sem);
    let mutex=esp_sdk_mutex_create(1);if !esp_sdk_mutex_lock(mutex) || !esp_sdk_mutex_lock(mutex) || !esp_sdk_mutex_unlock(mutex) || !esp_sdk_mutex_unlock(mutex) || esp_sdk_mutex_unlock(mutex) {return 11;}esp_sdk_free(mutex);
    let q=esp_sdk_queue_create(2,8);let word=alloc(8);store64(word,17);if !esp_sdk_queue_op(q,word,0,1) {return 12;}store64(word,29);if !esp_sdk_queue_op(q,word,0,2) || esp_sdk_queue_op(q,word,0,1) || !esp_sdk_queue_op(q,word,0,0) || load64(word)!=29 || !esp_sdk_queue_op(q,word,0,0) || load64(word)!=17 || esp_sdk_queue_op(q,word,1,0) {return 13;}esp_sdk_free(q);
    let event=esp_sdk_event_create();if esp_sdk_event_set(event,3)!=3 || esp_sdk_event_wait(event,3,1,1,0)!=3 || esp_sdk_event_wait(event,3,0,0,1)!=0 {return 14;}esp_sdk_free(event);
    sdk_queue=esp_sdk_queue_create(1,8);sdk_sem=esp_sdk_sem_create(1,0);sdk_event=esp_sdk_event_create();task=esp_sdk_task_create(esp32_callback32(producer),0,8192,1);if !task {return 15;}
    if !esp_sdk_queue_op(sdk_queue,word,100,0) || load64(word)!=914 || !esp_sdk_sem_take(sdk_sem,100) || esp_sdk_event_wait(sdk_event,7,1,1,100)!=7 {return 16;}
    while load64(task+544)!=2 {esp_sdk_yield();}esp_sdk_task_reap(task);esp_sdk_free(sdk_queue);esp_sdk_free(sdk_sem);esp_sdk_free(sdk_event);if esp_sdk_heap_free()!=free {return 17;}
    esp_uart_write("PASS: SDK arena split/coalesce, realloc failure, C tasks, delay, reclamation, queues, semaphores, mutexes and events\r\n");esp_uart_flush();return 0;
}
