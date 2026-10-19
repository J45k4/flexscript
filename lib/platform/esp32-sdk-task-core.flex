import "esp32-sdk-heap.flex";
import "esp32-sdk-task-select.flex";
// Priority-aware cooperative single-core scheduler. Architecture wrappers preserve the task CPU state on yield.
// Priorities0..24; equal-priority peers rotate. Timer-driven preemption is separate.
// Callbacks never switch tasks inside an ISR. The architecture wrapper supplies monotonic us.
// TCB: context[512], stack, C function, argument, next, state, priority,
//      wake_us, thread semaphore, stack_size, radio domain; wait fields592..624.
// State1=ready/delayed,2=deleted,3=blocked. Main starts at priority0.
global esp_sdk_current=0;
global esp_sdk_tasks=0;
global esp_sdk_yields=0;
global esp_sdk_reschedule_requested=0;
fn esp_sdk_reschedule_request() {esp_sdk_reschedule_requested=1;return 0;}
// Blocking/switching requires ordinary task context with interrupts unmasked.
fn esp_sdk_can_block() {if !esp_sdk_current || esp32_load32(esp32_state()+16) {return 0;}let ps=esp32_irq_save();esp32_irq_restore(ps);return !esp_sdk_irq_blocked(ps);}
fn esp_sdk_now() {let ps=esp32_irq_save();let now=esp_sdk_clock_now();esp32_irq_restore(ps);return now;}
fn esp_sdk_task_init() {
    if esp32_load32(esp32_state()+16) {return -16;}if !esp_sdk_task_profile_valid() {return -95;}if esp_sdk_current {return -16;}let main=esp_sdk_calloc(1,640);if !main {return -12;}
    let clock=esp_sdk_clock_init();if clock {esp_sdk_free(main);return clock;}
    esp_sdk_current=main;esp_sdk_tasks=main;store64(main+536,main);store64(main+544,1);
    return 0;
}
fn esp_sdk_yield() {
    if !esp_sdk_current || esp32_load32(esp32_state()+16) {return -16;}
    let ps=esp32_irq_save();if esp_sdk_irq_blocked(ps) {esp32_irq_restore(ps);return -16;}let previous=esp_sdk_current;let next=esp_sdk_task_choose(previous,esp_sdk_now());
    while !next {
        // Reevaluate under the IRQ mask after allowing device IRQs to wake a
        // blocked task. No task is made runnable merely to poll its object.
        esp32_irq_restore(ps);ps=esp32_irq_save();next=esp_sdk_task_choose(previous,esp_sdk_now());
    }
    if next!=previous {esp_sdk_current=next;esp_sdk_context_select(next);esp_sdk_yields=esp_sdk_yields+1;esp32_switch(previous,next);}
    esp32_irq_restore(ps);return 0;
}
fn esp_sdk_task_wait(kind,object,bits,all,deadline) {
    if !esp_sdk_current || !object || kind<1 || kind>5 || esp32_load32(esp32_state()+16) {return -16;}
    let ps=esp32_irq_save();if esp_sdk_irq_blocked(ps) {esp32_irq_restore(ps);return -16;}let task=esp_sdk_current;
    store64(task+592,kind);store64(task+600,object);store64(task+608,bits);store64(task+616,all);store64(task+560,deadline);store64(task+544,3);
    // Selection checks the predicate again while masked. A give/IRQ between
    // the caller's failed try and publication cannot leave a lost wakeup.
    esp32_irq_restore(ps);esp_sdk_yield();ps=esp32_irq_save();store64(task+544,1);store64(task+560,0);store64(task+592,0);store64(task+600,0);store64(task+608,0);store64(task+616,0);esp32_irq_restore(ps);return 0;
}
fn esp_sdk_task_get_priority(task) {
    if !task {task=esp_sdk_current;}let ps=esp32_irq_save();let member=esp_sdk_task_linked(esp_sdk_tasks,task);let priority= -22;if member {priority=load64(member+552);}esp32_irq_restore(ps);return priority;
}
fn esp_sdk_task_set_priority(task,priority) {
    if priority<0 || priority>24 || esp32_load32(esp32_state()+16) {return -22;}if !task {task=esp_sdk_current;}
    let ps=esp32_irq_save();let member=esp_sdk_task_linked(esp_sdk_tasks,task);if !member || load64(member+544)==2 {esp32_irq_restore(ps);return -22;}
    store64(member+552,priority);esp32_irq_restore(ps);return 0;
}
fn esp_sdk_delay(ticks) {if !esp_sdk_current || esp32_load32(esp32_state()+16) {return -16;}let ps=esp32_irq_save();if esp_sdk_irq_blocked(ps) {esp32_irq_restore(ps);return -16;}store64(esp_sdk_current+560,esp_sdk_now()+ticks*1000);esp32_irq_restore(ps);esp_sdk_yield();ps=esp32_irq_save();store64(esp_sdk_current+560,0);esp32_irq_restore(ps);return 0;}
fn esp_sdk_task_entry(task) {
    esp_sdk_task_unmask();esp32_call32(load64(task+520),load64(task+528),0,0,0,0,0,0,0);
    store64(task+544,2);while 1 {esp_sdk_yield();}return 0;
}
fn esp_sdk_task_create(function,argument,stack_size,priority) {
    if esp32_load32(esp32_state()+16) || !esp_sdk_current || !function || stack_size<2048 || stack_size>32768 || priority<0 || priority>24 {return 0;}stack_size=(stack_size+15)&~15;let allocation=esp_sdk_stack_bytes(stack_size);if allocation<stack_size {return 0;}
    let task=esp_sdk_calloc(1,640);if !task {return 0;}let stack=esp_sdk_malloc(allocation);if !stack {esp_sdk_free(task);return 0;}
    let result=esp_sdk_context_init(task,stack,allocation);if result {esp_sdk_free(stack);esp_sdk_free(task);return 0;}
    store64(task+512,stack);store64(task+520,function);store64(task+528,argument);store64(task+544,1);store64(task+552,priority);store64(task+576,allocation);
    let ps=esp32_irq_save();store64(task+536,load64(esp_sdk_current+536));store64(esp_sdk_current+536,task);esp32_irq_restore(ps);return task;
}
fn esp_sdk_task_delete(task) {
    if esp32_load32(esp32_state()+16) {return -16;}if !task {task=esp_sdk_current;}if !task {return -22;}let ps=esp32_irq_save();if task==esp_sdk_current && esp_sdk_irq_blocked(ps) {esp32_irq_restore(ps);return -16;}
    if !esp_sdk_task_linked(esp_sdk_tasks,task) {esp32_irq_restore(ps);return -22;}
    store64(task+544,2);esp32_irq_restore(ps);if task==esp_sdk_current {while 1 {esp_sdk_yield();}}return 0;
}
// Completed task memory is reclaimed explicitly from a different task.
fn esp_sdk_task_reap(task) {
    if esp32_load32(esp32_state()+16) {return -16;}let ps=esp32_irq_save();
    if !task || task==esp_sdk_current || task==esp_sdk_tasks || !esp_sdk_task_linked(esp_sdk_tasks,task) {esp32_irq_restore(ps);return -22;}
    if load64(task+544)!=2 {esp32_irq_restore(ps);return -22;}let before=esp_sdk_tasks;
    while load64(before+536)!=task {before=load64(before+536);}
    store64(before+536,load64(task+536));let thread_sem=load64(task+568);store64(task+568,0);esp32_irq_restore(ps);
    // The lazy thread semaphore belongs to this TCB, including when its C
    // entry returns normally instead of explicitly deleting the semaphore.
    esp_sdk_context_free(task);esp_sdk_free(thread_sem);esp_sdk_free(load64(task+512));esp_sdk_free(task);return 0;
}
