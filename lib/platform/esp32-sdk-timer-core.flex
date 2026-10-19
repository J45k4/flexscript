import "esp32-sdk-task-core.flex";
// SDK software timers execute in a task, never on the interrupt stack.
// Nodes: next, SDK timer address, C callback, argument, due_us, period_us.
global esp_sdk_timers=0;
global esp_sdk_timer_task=0;
global esp_sdk_timer_active=0;
fn esp_sdk_timer_find(key) {let t=esp_sdk_timers;while t && load64(t+8)!=key {t=load64(t);}return t;}
fn esp_sdk_timer_done(key) {
    let ps=esp32_irq_save();let t=esp_sdk_timers;let before=0;
    while t && load64(t+8)!=key {before=t;t=load64(t);}if t {if before {store64(before,load64(t));}else {esp_sdk_timers=load64(t);}esp_sdk_free(t);}esp32_irq_restore(ps);return 0;
}
fn esp_sdk_timer_setfn(key,function,argument) {
    if !key || !function {return -22;}let ps=esp32_irq_save();let t=esp_sdk_timer_find(key);
    if !t {t=esp_sdk_calloc(1,48);if !t {esp32_irq_restore(ps);return -12;}store64(t,esp_sdk_timers);store64(t+8,key);esp_sdk_timers=t;}
    store64(t+16,function);store64(t+24,argument);store64(t+32,0);store64(t+40,0);esp32_irq_restore(ps);return 0;
}
fn esp_sdk_timer_arm(key,us,repeat) {let ps=esp32_irq_save();let t=esp_sdk_timer_find(key);if !t || us<0 {esp32_irq_restore(ps);return -22;}if !us {us=1;}store64(t+32,esp_sdk_now()+us);let period=0;if repeat {period=us;}store64(t+40,period);esp32_irq_restore(ps);return 0;}
fn esp_sdk_timer_disarm(key) {let ps=esp32_irq_save();let t=esp_sdk_timer_find(key);if t {store64(t+32,0);}esp32_irq_restore(ps);return 0;}
fn esp_sdk_timer_poll() {
    // Restart traversal after each callback: callbacks may delete/rearm timers.
    if !esp_sdk_can_block() {return -16;}let count=0;while count<64 {let ps=esp32_irq_save();let now=esp_sdk_now();let t=esp_sdk_timers;
        while t && (!load64(t+32) || load64(t+32)>now) {t=load64(t);}if !t {esp32_irq_restore(ps);return count;}
        let function=load64(t+16);let arg=load64(t+24);let period=load64(t+40);let next=0;if period {next=now+period;}store64(t+32,next);esp_sdk_timer_active=esp_sdk_timer_active+1;esp32_irq_restore(ps);
        esp32_call32(function,arg,0,0,0,0,0,0,0);ps=esp32_irq_save();esp_sdk_timer_active=esp_sdk_timer_active-1;esp32_irq_restore(ps);count=count+1;
    }return count;
}
fn esp_sdk_timer_worker(a,b,c,d,e,f,g,h) {while 1 {esp_sdk_timer_poll();esp_sdk_delay(1);}return 0;}
// Publish or reclaim the service TCB atomically; it may run after unmasking.
fn esp_sdk_timer_init() {let ps=esp32_irq_save();if esp_sdk_timer_task {esp32_irq_restore(ps);return -16;}esp_sdk_timer_task=esp_sdk_task_create(esp32_callback32(esp_sdk_timer_worker),0,8192,2);if !esp_sdk_timer_task {esp32_irq_restore(ps);return -12;}esp32_irq_restore(ps);return 0;}

// Shared service can be reclaimed only after all timer users are gone. A
// callback may yield, so checking just the current task would be insufficient.
fn esp_sdk_timer_deinit() {let ps=esp32_irq_save();
    if esp_sdk_timers || esp_sdk_timer_active || esp_sdk_current==esp_sdk_timer_task || esp32_load32(esp32_state()+16) {esp32_irq_restore(ps);return -16;}
    if !esp_sdk_timer_task {esp32_irq_restore(ps);return 0;}let task=esp_sdk_timer_task;let r=esp_sdk_task_delete(task);if r {esp32_irq_restore(ps);return r;}r=esp_sdk_task_reap(task);if !r {esp_sdk_timer_task=0;}esp32_irq_restore(ps);return r;
}
