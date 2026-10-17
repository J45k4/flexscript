import "../../lib/platform/esp32-xip.flex";
import "../../lib/platform/esp32.flex";
import "../../lib/platform/esp32-irq.flex";
import "../../lib/platform/esp32-sdk-sync.flex";
global sp_error=0;
global sp_checks=0;
global sp_trace=0;
global sp_used=0;
global sp_object=0;
global sp_word=0;
global sp_kind=0;
global sp_wait_done=0;
global sp_irq_count=0;
global sp_high=0;
global sp_middle=0;
fn sp_check(ok,code) {sp_checks=sp_checks+1;if !ok && !sp_error {sp_error=code;esp_uart_write("PRIORITY FAIL ");esp_uart_hex(code);esp_uart_write("\r\n");}return ok;}
fn sp_record(value) {if sp_used<128 {store64(sp_trace+sp_used*8,value);sp_used=sp_used+1;}else {sp_check(0,90);}return 0;}
fn sp_worker(a,b,c,d,e,f,g,h) {
    let marker=0x3f000000+a;esp32_call32(esp32_external("c_set_fpu"),marker,0,0,0,0,0,0,0);esp32_call32(esp32_external("c_set_thread"),a+1000,0,0,0,0,0,0,0);
    let i=0;while i<2 {sp_record(a);esp_sdk_yield();sp_check(esp32_call32(esp32_external("c_read_fpu"),0,0,0,0,0,0,0,0)==marker,91);sp_check(esp32_call32(esp32_external("c_read_thread"),0,0,0,0,0,0,0,0)==a+1000,92);i=i+1;}return 0;
}
fn sp_join(task) {while load64(task+544)!=2 {esp_sdk_yield();}return esp_sdk_task_reap(task);}
fn sp_waiter(a,b,c,d,e,f,g,h) {
    sp_record(100);let result=0;
    if sp_kind==1 {result=esp_sdk_sem_take(sp_object,100);}
    if sp_kind==2 {let word=esp_sdk_malloc(8);result=esp_sdk_queue_op(sp_object,word,100,0);sp_check(result && load64(word)==42,101);esp_sdk_free(word);}
    if sp_kind==3 {result=esp_sdk_event_wait(sp_object,3,1,1,100)==3;}
    if sp_kind==4 {let word=esp_sdk_malloc(8);store64(word,42);result=esp_sdk_queue_op(sp_object,word,100,1);esp_sdk_free(word);}
    sp_check(result,102);sp_wait_done=1;sp_record(400);return 0;
}
fn sp_producer(a,b,c,d,e,f,g,h) {
    sp_record(300);
    if sp_kind==1 {sp_check(esp_sdk_sem_give(sp_object),103);}
    if sp_kind==2 {store64(sp_word,42);sp_check(esp_sdk_queue_op(sp_object,sp_word,0,1),104);}
    if sp_kind==3 {sp_check(esp_sdk_event_set(sp_object,3)==3,105);}
    if sp_kind==4 {sp_check(esp_sdk_queue_op(sp_object,sp_word,0,0) && load64(sp_word)==17,106);}
    return 0;
}
fn sp_medium(a,b,c,d,e,f,g,h) {sp_record(200);esp_sdk_yield();sp_record(201);return 0;}
fn sp_mutex_high(a,b,c,d,e,f,g,h) {
    sp_record(15);sp_check(esp_sdk_mutex_lock(sp_object),111);sp_record(30);sp_check(esp_sdk_mutex_unlock(sp_object),112);return 0;
}
fn sp_mutex_middle(a,b,c,d,e,f,g,h) {sp_record(40);return 0;}
fn sp_mutex_low(a,b,c,d,e,f,g,h) {
    sp_check(esp_sdk_mutex_lock(sp_object) && esp_sdk_mutex_lock(sp_object),113);sp_record(10);
    sp_middle=esp_sdk_task_create(esp32_callback32(sp_mutex_middle),0,4096,5);sp_high=esp_sdk_task_create(esp32_callback32(sp_mutex_high),0,4096,9);sp_check(sp_middle && sp_high,114);
    esp_sdk_yield();sp_check(load64(esp_sdk_current+624)==9 && esp_sdk_task_get_priority(0)==1,115);sp_record(20);
    sp_check(esp_sdk_mutex_unlock(sp_object),116);esp_sdk_yield();sp_check(load64(esp_sdk_current+624)==9,117);
    sp_check(esp_sdk_mutex_unlock(sp_object),118);esp_sdk_yield();sp_check(load64(esp_sdk_current+624)==1,119);sp_record(50);return 0;
}
fn sp_irq(source) {esp_timer_ack(0,0);esp_timer_stop(0);sp_irq_count=sp_irq_count+1;sp_check(esp_sdk_yield()== -16,121);sp_check(esp_sdk_sem_give(sp_object),122);return 0;}
fn sp_api_checks() {
    let before=esp_sdk_heap_free();sp_check(esp_sdk_task_get_priority(0)==0,81);
    sp_check(!esp_sdk_task_create(esp32_callback32(sp_worker),0,4096,-1) && !esp_sdk_task_create(esp32_callback32(sp_worker),0,4096,25) && esp_sdk_heap_free()==before,82);
    sp_check(esp_sdk_task_set_priority(0,-1)== -22 && esp_sdk_task_set_priority(0,25)== -22 && esp_sdk_task_get_priority(0)==0,83);
    sp_check(esp_sdk_task_get_priority(0x123456)== -22 && esp_sdk_task_set_priority(0x123456,5)== -22,84);
    sp_check(!esp_sdk_task_set_priority(0,24) && esp_sdk_task_get_priority(0)==24 && !esp_sdk_task_set_priority(0,0),85);return 0;
}
fn main() {
    esp_uart_write("START: SDK priorities\r\n");if esp_sdk_heap_init(0x3ffc8000,98304) || esp_sdk_task_init() {return 1;}esp32_irq_restore(0);
    sp_trace=alloc(1024);sp_word=alloc(8);let before=esp_sdk_heap_free();
    let a=esp_sdk_task_create(esp32_callback32(sp_worker),3,4096,3);let b=esp_sdk_task_create(esp32_callback32(sp_worker),9,4096,9);let c=esp_sdk_task_create(esp32_callback32(sp_worker),5,4096,5);if !a || !b || !c {return 2;}
    sp_join(a);sp_join(b);sp_join(c);sp_check(sp_used==6,3);let expected=0x030305050909;let i=0;while i<6 {sp_check(load64(sp_trace+i*8)==((expected>>(i*8))&255),4+i);i=i+1;}sp_check(esp_sdk_heap_free()==before,10);if sp_error {return sp_error;}
    sp_used=0;a=esp_sdk_task_create(esp32_callback32(sp_worker),11,4096,7);b=esp_sdk_task_create(esp32_callback32(sp_worker),22,4096,7);c=esp_sdk_task_create(esp32_callback32(sp_worker),33,4096,7);if !a || !b || !c {return 11;}
    sp_join(a);sp_join(b);sp_join(c);sp_check(sp_used==6,12);expected=0x0b16210b1621;i=0;while i<6 {sp_check(load64(sp_trace+i*8)==((expected>>(i*8))&255),13+i);i=i+1;}sp_check(esp_sdk_heap_free()==before,19);if sp_error {return sp_error;}
    sp_api_checks();if sp_error {return sp_error;}
    sp_kind=1;while sp_kind<=4 {
        sp_used=0;sp_wait_done=0;sp_object=0;if sp_kind==1 {sp_object=esp_sdk_sem_create(1,0);}if sp_kind==2 || sp_kind==4 {sp_object=esp_sdk_queue_create(1,8);}if sp_kind==3 {sp_object=esp_sdk_event_create();}if !sp_object {return 20;}
        if sp_kind==4 {store64(sp_word,17);sp_check(esp_sdk_queue_op(sp_object,sp_word,0,1),21);}
        a=esp_sdk_task_create(esp32_callback32(sp_producer),0,4096,1);b=esp_sdk_task_create(esp32_callback32(sp_medium),0,4096,5);c=esp_sdk_task_create(esp32_callback32(sp_waiter),0,4096,9);if !a || !b || !c {return 22;}
        sp_join(a);sp_join(b);sp_join(c);sp_check(sp_wait_done && sp_used==5,23);sp_check(load64(sp_trace)==100 && load64(sp_trace+8)==200 && load64(sp_trace+16)==201 && load64(sp_trace+24)==300 && load64(sp_trace+32)==400,24);
        if sp_kind==3 {sp_check(!load64(sp_object),25);}if sp_kind==4 {sp_check(esp_sdk_queue_op(sp_object,sp_word,0,0) && load64(sp_word)==42,26);}
        esp_sdk_free(sp_object);sp_check(esp_sdk_heap_free()==before,27);if sp_error {return sp_error;}sp_kind=sp_kind+1;
    }
    sp_used=0;sp_object=esp_sdk_mutex_create(1);a=esp_sdk_task_create(esp32_callback32(sp_mutex_low),0,4096,1);if !sp_object || !a {return 30;}sp_join(a);sp_join(sp_high);sp_join(sp_middle);
    sp_check(sp_used==6 && load64(sp_trace)==10 && load64(sp_trace+8)==15 && load64(sp_trace+16)==20 && load64(sp_trace+24)==30 && load64(sp_trace+32)==40 && load64(sp_trace+40)==50,31);esp_sdk_free(sp_object);sp_check(esp_sdk_heap_free()==before,32);if sp_error {return sp_error;}
    // With no other task runnable, the scheduler must allow an actual device
    // interrupt to satisfy the wait. A nested IRQ mask would lose this wake.
    sp_object=esp_sdk_sem_create(1,0);if !sp_object || esp_timer_init(0,80,0) || esp_timer_alarm(0,5000,0) || esp_irq_attach(esp_timer_source(0),esp32_callback(sp_irq)) {return 40;}esp_irq_enable();esp_timer_start(0);
    sp_check(esp_sdk_sem_take(sp_object,100) && sp_irq_count==1,41);esp_irq_detach(esp_timer_source(0));esp_timer_stop(0);
    let began=esp_sdk_now();sp_check(!esp_sdk_sem_take(sp_object,2) && esp_sdk_now()-began>=2000 && load64(esp_sdk_current+544)==1 && !load64(esp_sdk_current+600),42);
    esp_sdk_free(sp_object);sp_check(esp_sdk_heap_free()==before,43);if sp_error {return sp_error;}
    esp_uart_write("PASS: SDK priority selection, peer rotation, blocking, inheritance, IRQ wake and context state; checks=");esp_uart_hex(sp_checks);esp_uart_write("\r\n");esp_uart_flush();return 0;
}
