import "esp32-sdk-heap.flex";
import "esp32-timer.flex";
// Cooperative single-core scheduler. C windows/FPU remain live across a yield.
// Callbacks never switch tasks inside an ISR. Timer2 supplies monotonic us.
// TCB: context[512], stack, C function, argument, next, state, priority,
//      wake_us, thread semaphore, stack_size, radio domain. State 1=ready, 2=deleted.
global esp_sdk_current=0;
global esp_sdk_tasks=0;
global esp_sdk_yields=0;
fn esp_sdk_now() {return esp_timer_read(2);}
fn esp_sdk_task_init() {
    if esp_sdk_current {return -16;}let main=esp_sdk_calloc(1,640);if !main {return -12;}
    esp_sdk_current=main;esp_sdk_tasks=main;store64(main+536,main);store64(main+544,1);
    esp_timer_init(2,80,0);esp_timer_start(2);return 0;
}
fn esp_sdk_yield() {
    if !esp_sdk_current || esp32_load32(esp32_state()+16) {return -16;}let ps=esp32_irq_save();let previous=esp_sdk_current;let next=load64(previous+536);let now=esp_sdk_now();
    while next!=previous && (load64(next+544)!=1 || load64(next+560)>now) {next=load64(next+536);}
    if next==previous && (load64(next+544)!=1 || load64(next+560)>now) {
        // No runnable task. Interrupts must remain enabled so devices can wake us.
        esp32_irq_restore(ps);let ready=0;while !ready {now=esp_sdk_now();next=load64(next+536);ready=load64(next+544)==1 && load64(next+560)<=now;}ps=esp32_irq_save();
    }
    if next!=previous {esp_sdk_current=next;esp_sdk_yields=esp_sdk_yields+1;esp32_switch(previous,next);}
    esp32_irq_restore(ps);return 0;
}
fn esp_sdk_delay(ticks) {if !esp_sdk_current {return -16;}store64(esp_sdk_current+560,esp_sdk_now()+ticks*1000);esp_sdk_yield();store64(esp_sdk_current+560,0);return 0;}
fn esp_sdk_task_entry(task) {
    esp32_irq_restore(0);esp32_call32(load64(task+520),load64(task+528),0,0,0,0,0,0,0);
    store64(task+544,2);while 1 {esp_sdk_yield();}return 0;
}
fn esp_sdk_task_create(function,argument,stack_size,priority) {
    if !esp_sdk_current || !function || stack_size<2048 || stack_size>32768 {return 0;}stack_size=(stack_size+15)&~15;
    let task=esp_sdk_calloc(1,640);if !task {return 0;}let stack=esp_sdk_malloc(stack_size);if !stack {esp_sdk_free(task);return 0;}
    let top=stack+stack_size-16;store64(top,task);esp32_store32(task+4,top);esp32_store32(task+256,esp32_callback(esp_sdk_task_entry));esp32_store32(task+264,1);esp32_store32(task+272,15);esp32_store32(task+292,1);esp32_store32(task+304,stack);
    store64(task+512,stack);store64(task+520,function);store64(task+528,argument);store64(task+544,1);store64(task+552,priority);store64(task+576,stack_size);
    let ps=esp32_irq_save();store64(task+536,load64(esp_sdk_current+536));store64(esp_sdk_current+536,task);esp32_irq_restore(ps);return task;
}
fn esp_sdk_task_delete(task) {
    if !task {task=esp_sdk_current;}if !task {return -22;}let ps=esp32_irq_save();let p=esp_sdk_tasks;
    while p!=task && load64(p+536)!=esp_sdk_tasks {p=load64(p+536);}if p!=task {esp32_irq_restore(ps);return -22;}
    store64(task+544,2);esp32_irq_restore(ps);if task==esp_sdk_current {while 1 {esp_sdk_yield();}}return 0;
}
// Completed task memory is reclaimed explicitly from a different task.
fn esp_sdk_task_reap(task) {
    if !task || task==esp_sdk_current || task==esp_sdk_tasks || load64(task+544)!=2 {return -22;}let ps=esp32_irq_save();let before=esp_sdk_tasks;
    while load64(before+536)!=task && load64(before+536)!=esp_sdk_tasks {before=load64(before+536);}if load64(before+536)!=task {esp32_irq_restore(ps);return -22;}
    store64(before+536,load64(task+536));let thread_sem=load64(task+568);store64(task+568,0);esp32_irq_restore(ps);
    // The lazy thread semaphore belongs to this TCB, including when its C
    // entry returns normally instead of explicitly deleting the semaphore.
    esp_sdk_free(thread_sem);esp_sdk_free(load64(task+512));esp_sdk_free(task);return 0;
}
