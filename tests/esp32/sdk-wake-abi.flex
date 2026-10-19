import "../../lib/platform/esp32-xip.flex";
import "../../lib/platform/esp32-sdk-preempt.flex";
import "../../lib/platform/esp32-bluetooth.flex";
global wa_checks=0;
global wa_error=0;
global wa_object=0;
global wa_item=0;
global wa_mode=0;
global wa_woken=0;
global wa_irqs=0;
global wa_c_error=0;
fn wa_check(ok,code) {wa_checks=wa_checks+1;if !ok && !wa_error {wa_error=code;esp_uart_write("WAKE FAIL ");esp_uart_hex(code);esp_uart_write("\r\n");}return ok;}
fn wa_callback(mode) {
    if mode==0 {return esp32_callback32(esp_radio_cb_send_isr);}if mode==1 {return esp32_callback32(esp_bt_sem_give_isr);}if mode==2 {return esp32_callback32(esp_bt_recv_isr);}return esp32_callback32(esp_bt_sem_take_isr);
}
fn wa_invoke(mode,object,item,flags,result,flag,chain) {
    let sem=mode&1;return esp32_call32(esp32_external("c_wake_invoke"),wa_callback(mode),object,item,sem,flags,result,flag,chain);
}
fn wa_reset(tasks,mutex,mode,relation,object) {
    let i=0;while i<4 {let t=tasks+i*640;let j=0;while j<640 {store8(t+j,0);j=j+1;}store64(t+536,tasks+((i+1)%4)*640);store64(t+544,1);store64(t+624,100+i);store64(t+504,0x13572468);i=i+1;}
    store64(tasks+552,5);let waiter=tasks+640;store64(waiter+552,1);if relation==1 {store64(waiter+552,5);}if relation==2 || relation==5 {store64(waiter+552,9);}store64(waiter+544,3);store64(waiter+560,0x7fffffffffffffff);
    let kind=3;if mode==1 || mode==3 {kind=1;}if mode==2 {kind=4;}if relation==3 {kind=5;}store64(waiter+592,kind);store64(waiter+600,object);if relation==6 {store64(waiter+544,2);}
    if relation==4 || relation==5 {let donor=tasks+1280;store64(donor+552,24);store64(donor+544,3);store64(donor+560,1);store64(donor+592,2);store64(donor+600,mutex);let owner=waiter;if relation==5 {owner=tasks;}store64(mutex,owner);}return 0;
}
fn wa_irq(source) {
    if esp_timer_pending(0) {esp_timer_ack(0,0);esp_timer_stop(0);wa_irqs=wa_irqs+1;wa_c_error=wa_invoke(wa_mode,wa_object,wa_item,0,1,1,1);}return 0;
}
fn wa_waiter(a,b,c,d,e,f,g,h) {
    let ok=0;if wa_mode==0 {ok=esp_sdk_queue_op(wa_object,wa_item+8,200,0) && load8(wa_item+8)==0x42;}
    if wa_mode==1 {ok=esp_sdk_sem_take(wa_object,200);}if wa_mode==2 {ok=esp_sdk_queue_op(wa_object,wa_item+8,200,1);}
    wa_check(ok,701);wa_woken=1;return 0;
}
fn wa_busy(a,b,c,d,e,f,g,h) {esp_timer_start(0);while !wa_woken {}return 0;}
fn wa_join(t) {while load64(t+544)!=2 {esp_sdk_yield();}return esp_sdk_task_reap(t);}
fn main() {
    if esp_sdk_heap_init(0x3ffc8000,98304) || esp_sdk_task_init() {return 1;}esp_irq_enable();let baseline=esp_sdk_heap_free();let queue=esp_sdk_queue_create(1,7);let sem=esp_sdk_sem_create(1,0);wa_item=alloc(24);let tasks=alloc(4*640);let mutex=alloc(8);let mode=0;let calls=0;
    // ABI/state queries use explicit synthetic TCBs under the IRQ mask. The
    // separate phase below verifies real blocked tasks and actual IRQ returns.
    while mode<4 {let relation=0;while relation<7 {let initial=0;while initial<2 {let null=0;while null<2 {let alignment=0;while alignment<2 {let failed=0;while failed<2 {
        let ps=esp32_irq_save();let saved_current=esp_sdk_current;let saved_tasks=esp_sdk_tasks;let object=queue;if mode&1 {object=sem;}
        wa_reset(tasks,mutex,mode,relation,object);esp_sdk_current=tasks;esp_sdk_tasks=tasks;
        let value=failed;if mode==2 || mode==3 {value=!failed;}if mode&1 {store64(sem+8,value);}else {store64(queue+24,value);}
        let expected=initial;if !failed && mode!=3 && (relation==2 || relation==4 || relation==5) && !null {expected=1;}
        let result=wa_invoke(mode,object,wa_item,initial|(null<<8)|(alignment<<9),!failed,expected,!failed && expected && !initial && !null);calls=calls+1;
        let clean=1;let i=0;while i<4 {if load64(tasks+i*640+624)!=100+i || load64(tasks+i*640+504)!=0x13572468 {clean=0;}i=i+1;}
        esp_sdk_current=saved_current;esp_sdk_tasks=saved_tasks;esp32_irq_restore(ps);wa_check(result==0,1000+result);wa_check(clean,2000);if wa_error {return wa_error;}
        failed=failed+1;}alignment=alignment+1;}null=null+1;}initial=initial+1;}relation=relation+1;}mode=mode+1;}
    esp_sdk_free(queue);esp_sdk_free(sem);wa_check(esp_sdk_heap_free()==baseline,3000);wa_check(calls==448,3001);
    if esp_timer_init(0,80,0) || esp_irq_attach(14,esp32_callback(wa_irq)) {return 2;}
    wa_mode=0;while wa_mode<3 {
        wa_woken=0;wa_irqs=0;wa_c_error=0;wa_object=esp_sdk_queue_create(1,7);if wa_mode==1 {esp_sdk_free(wa_object);wa_object=esp_sdk_sem_create(1,0);}if !wa_object {return 3;}store8(wa_item,0x42);store8(wa_item+8,0x73);if wa_mode==2 && !esp_sdk_queue_try(wa_object,wa_item,1) {return 4;}
        if esp_timer_set(0,0) || esp_timer_alarm(0,30000,0) || esp_sdk_preempt_start(1000000) {return 5;}let ticks=esp_sdk_preempt_ticks;let begin=esp_sdk_now();let setup_ps=esp32_irq_save();let low=esp_sdk_task_create(esp32_callback32(wa_busy),0,8192,1);let high=esp_sdk_task_create(esp32_callback32(wa_waiter),0,8192,9);esp32_irq_restore(setup_ps);if !low || !high {return 6;}
        wa_join(low);wa_join(high);wa_check(wa_woken && wa_irqs==1 && !wa_c_error && esp_sdk_preempt_ticks==ticks && esp_sdk_now()-begin<500000,4000+wa_c_error);wa_check(!esp_sdk_preempt_stop(),5000);
        if wa_mode==2 {wa_check(esp_sdk_queue_try(wa_object,wa_item,0) && load8(wa_item)==0x73,6000);}esp_sdk_free(wa_object);wa_check(esp_sdk_heap_free()==baseline && !esp32_load32(esp32_state()+16),7000);if wa_error {return wa_error;}wa_mode=wa_mode+1;
    }
    esp_irq_detach(14);wa_check(esp32_load32(esp32_external("c_wake_calls"))==451,8000);esp_uart_write("PASS:448 guarded C bool ABI cases, accumulated hints and3 real ISR priority wakes; checks=");esp_uart_hex(wa_checks);esp_uart_write("\r\n");return wa_error;
}
