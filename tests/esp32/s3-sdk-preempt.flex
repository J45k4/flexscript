// ESP32-S3 RAM counterpart of sdk-preempt.flex; full C state matrix.
import "../../lib/platform/esp32s3-sdk-preempt.flex";
import "../../lib/platform/esp32s3-sdk-sync.flex";
global pt_state=0;
global pt_depth=0;
global pt_error=0;
global pt_checks=0;
global pt_sem=0;
global pt_woken=0;
global pt_irqs=0;
global pt_clobbers=0;
fn pt_check(ok,code) {pt_checks=pt_checks+1;if !ok && !pt_error {pt_error=code;esp_uart_write("PREEMPT FAIL ");esp_uart_hex(code);esp_uart_write("\r\n");}return ok;}
fn pt_busy(a,b,c,d,e,f,g,h) {
    let result=esp32_call32(esp32_external("c_preempt_busy"),pt_state,a,pt_depth,0x3f000000+a*65536,0,0,0,0);pt_check(result==0,100+result);return 0;
}
fn pt_join(task) {while load64(task+544)!=2 {esp_sdk_yield();}return esp_sdk_task_reap(task);}
fn pt_app_irq(source) {
    if esp_timer_pending(0) {esp_timer_ack(0,0);esp_timer_stop(0);pt_irqs=pt_irqs+1;pt_check(esp_sdk_yield()== -16 && esp_sdk_preempt_stop()== -16,201);pt_check(esp_sdk_sem_give(pt_sem),202);}return 0;
}
fn pt_high(a,b,c,d,e,f,g,h) {pt_check(esp_sdk_sem_take(pt_sem,200),203);pt_woken=1;return 0;}
fn pt_low(a,b,c,d,e,f,g,h) {esp_timer_start(0);while !pt_woken {}return 0;}
fn pt_clobber_irq(source) {if esp_timer_pending(0) {esp_timer_ack(0,1);pt_clobbers=pt_clobbers+1;esp32_call32(esp32_external("c_preempt_irq_clobber"),0,0,0,0,0,0,0,0);esp_sdk_reschedule_request();}return 0;}
fn pt_unused(source) {return 0;}
fn main() {
    esp_uart_write("START: asynchronous C preemption\r\n");if esp_sdk_heap_init(0x3fcc6000,40960) || esp_sdk_task_init() {return 1;}esp_irq_enable();
    pt_state=alloc(32);let before=esp_sdk_heap_free();let base=esp_timer_base(3);let initial_mask=esp32_irq_enabled();let initial_route=esp32_load32(0x600c20d8);
    pt_check(esp32_preempt_supported()==1 && !esp_sdk_preempt_stop(),1);let native_before=esp32_load32(esp32_state());
    pt_check(esp_sdk_preempt_start(0)== -22 && esp_sdk_preempt_start(999)== -22 && esp_sdk_preempt_start(1000001)== -22 && esp32_load32(esp32_state())==native_before,2);
    esp_timer_init(3,321,0);esp_timer_set_words(3,0x55667788,0x00112233);esp32_store32(base+16,0x12345678);esp32_store32(base+20,0x00389abc);esp32_store32(base+24,0xabcdef01);esp32_store32(base+28,0x00056789);let config=esp32_load32(base);
    esp_timer_start(3);pt_check(esp_sdk_preempt_start(5000)== -16 && esp32_load32(base)==(config|(1<<31)),3);esp_timer_stop(3);esp_timer_set_words(3,0x55667788,0x00112233);esp32_store32(base+24,0xabcdef01);esp32_store32(base+28,0x00056789);
    pt_check(!esp_irq_attach(54,esp32_callback(pt_unused)),4);pt_check(esp_sdk_preempt_start(5000)== -16 && esp_irq_handler(54)==esp32_callback(pt_unused),5);esp_irq_detach(54);esp32_store32(0x600c20d8,initial_route);esp32_irq_mask(initial_mask);
    pt_check(!esp_sdk_preempt_start(5000) && esp_sdk_preempt_start(5000)== -16,6);let ps=esp32_irq_save();let ticks=esp_sdk_preempt_ticks;let begin=esp32_cycles();while ((esp32_cycles()-begin)&4294967295)<1600000 {}pt_check(esp_sdk_preempt_ticks==ticks,7);esp32_irq_restore(ps);esp_sdk_delay(20);if !pt_check(esp_sdk_preempt_ticks>=ticks+2,25) {esp_uart_write("LATE TICK count=");esp_uart_hex(esp_sdk_preempt_ticks);esp_uart_write(" timer=");esp_uart_hex(esp_timer_read(3));esp_uart_write(" alarm=");esp_uart_hex(esp32_load32(base+16));esp_uart_write(" cfg=");esp_uart_hex(esp32_load32(base));esp_uart_write("\r\n");return pt_error;}
    pt_check(!esp_timer_init(0,80,0) && !esp_timer_alarm(0,7000,1) && !esp_irq_attach(50,esp32_callback(pt_clobber_irq)) && !esp_timer_start(0),23);
    // Publish dependent peers before a higher-priority worker can starve main.
    let run=0;while run<3 {
        let i=0;while i<32 {store8(pt_state+i,0);i=i+1;}pt_depth=0;if run==1 {pt_depth=16;}if run==2 {pt_depth=40;}
        let setup_ps=esp32_irq_save();let a=esp_sdk_task_create(esp32_callback32(pt_busy),0,12288,5);let b=esp_sdk_task_create(esp32_callback32(pt_busy),1,12288,5);ticks=esp_sdk_preempt_switches;esp32_irq_restore(setup_ps);if !a || !b {return 8;}
        pt_join(a);pt_join(b);pt_check(esp32_load32(pt_state)==12 && esp32_load32(pt_state+4)==12 && esp32_load32(pt_state+8)==24 && esp_sdk_preempt_switches-ticks>=20,9);pt_check(esp_sdk_heap_free()==before && !esp32_load32(esp32_state()+16),10);if pt_error {return pt_error;}run=run+1;
    }
    esp_timer_stop(0);esp_timer_ack(0,0);esp_irq_detach(50);pt_check(pt_clobbers>0,24);
    pt_check(!esp_sdk_preempt_stop() && !esp_sdk_preempt_enabled && !esp_irq_handler(54) && esp32_irq_enabled()==initial_mask && esp32_load32(0x600c20d8)==initial_route,11);
    pt_check(esp32_load32(base)==config && esp32_load32(base+16)==0x12345678 && esp32_load32(base+20)==0x00389abc && esp32_load32(base+24)==0xabcdef01 && esp32_load32(base+28)==0x00056789,12);
    pt_check(!esp_timer_read_words(3,pt_state+16) && esp32_load32(pt_state+16)==0x55667788 && esp32_load32(pt_state+20)==0x00112233,13);native_before=esp32_load32(esp32_state());
    run=0;while run<4 {pt_check(!esp_sdk_preempt_start(5000) && !esp_sdk_preempt_stop() && esp32_load32(esp32_state())==native_before,14);run=run+1;}
    // An ordinary peripheral ISR must wake the higher-priority task before
    // the one-second tick. The low task never cooperates with the scheduler.
    pt_sem=esp_sdk_sem_create(1,0);if !pt_sem || esp_timer_init(0,80,0) || esp_timer_alarm(0,30000,0) || esp_irq_attach(50,esp32_callback(pt_app_irq)) || esp_sdk_preempt_start(1000000) {return 15;}
    ticks=esp_sdk_preempt_ticks;begin=esp_sdk_now();let setup_ps=esp32_irq_save();let low=esp_sdk_task_create(esp32_callback32(pt_low),0,8192,1);let high=esp_sdk_task_create(esp32_callback32(pt_high),0,8192,9);esp32_irq_restore(setup_ps);if !low || !high {return 16;}
    pt_join(low);pt_join(high);pt_check(pt_woken && pt_irqs==1 && esp_sdk_preempt_ticks==ticks && esp_sdk_now()-begin<500000,17);pt_check(!esp_sdk_preempt_stop(),18);
    // No task is runnable while main blocks. Repeated scheduler ticks must
    // return to the idle wait so the later application timer can wake main.
    pt_irqs=0;esp_timer_set(0,0);esp_timer_alarm(0,40000,0);pt_check(!esp_sdk_preempt_start(5000),19);ticks=esp_sdk_preempt_ticks;esp_timer_start(0);pt_check(esp_sdk_sem_take(pt_sem,200) && pt_irqs==1 && esp_sdk_preempt_ticks>ticks,20);pt_check(!esp_sdk_preempt_stop() && esp_irq_handler(50)==esp32_callback(pt_app_irq),21);
    esp_irq_detach(50);esp_sdk_free(pt_sem);pt_check(esp_sdk_heap_free()==before && !esp32_load32(esp32_state()+16),22);if pt_error {return pt_error;}
    esp_uart_write("PASS: forced C windows/LOOP/SAR/FPU/thread preemption, ISR wake, idle wait and timer ownership; checks=");esp_uart_hex(pt_checks);esp_uart_write(" switches=");esp_uart_hex(esp_sdk_preempt_switches);esp_uart_write(" ticks=");esp_uart_hex(esp_sdk_preempt_ticks);esp_uart_write("\r\n");esp_uart_flush();return 0;
}
