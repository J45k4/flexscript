import "esp32-sdk-task.flex";
// Millisecond ticks. 0xffffffff means wait forever; operations return 1/0.
fn esp_sdk_deadline(ticks) {if ticks==4294967295 {return 0x7fffffffffffffff;}return esp_sdk_now()+ticks*1000;}
fn esp_sdk_sem_create(maximum,initial) {if maximum<1 || initial>maximum {return 0;}let s=esp_sdk_calloc(1,32);if s {store64(s,maximum);store64(s+8,initial);}return s;}
fn esp_sdk_sem_take(s,ticks) {
    if !s {return 0;}let end=esp_sdk_deadline(ticks);while 1 {let ps=esp32_irq_save();let n=load64(s+8);if n {store64(s+8,n-1);esp32_irq_restore(ps);return 1;}esp32_irq_restore(ps);if !ticks || esp_sdk_now()>=end || esp32_load32(esp32_state()+16) {return 0;}esp_sdk_yield();}return 0;
}
fn esp_sdk_sem_give(s) {if !s {return 0;}let ps=esp32_irq_save();let n=load64(s+8);if n>=load64(s) {esp32_irq_restore(ps);return 0;}store64(s+8,n+1);esp32_irq_restore(ps);return 1;}
fn esp_sdk_mutex_create(recursive) {let m=esp_sdk_calloc(1,32);if m {store64(m+16,recursive);}return m;}
fn esp_sdk_mutex_lock(m) {
    if !m || esp32_load32(esp32_state()+16) {return 0;}while 1 {let ps=esp32_irq_save();let owner=load64(m);if !owner || (owner==esp_sdk_current && load64(m+16)) {store64(m,esp_sdk_current);store64(m+8,load64(m+8)+1);esp32_irq_restore(ps);return 1;}esp32_irq_restore(ps);esp_sdk_yield();}return 0;
}
fn esp_sdk_mutex_unlock(m) {if !m {return 0;}let ps=esp32_irq_save();let depth=load64(m+8);if !depth || load64(m)!=esp_sdk_current {esp32_irq_restore(ps);return 0;}depth=depth-1;store64(m+8,depth);if !depth {store64(m,0);}esp32_irq_restore(ps);return 1;}
// Queue: capacity, item_bytes, head, count, payload after 32-byte header.
fn esp_sdk_queue_create(capacity,item_bytes) {if capacity<1 || item_bytes<1 || item_bytes>4096 || capacity>65536/item_bytes {return 0;}let q=esp_sdk_calloc(1,32+capacity*item_bytes);if q {store64(q,capacity);store64(q+8,item_bytes);}return q;}
// Queue fields fit u32 by construction. Keep the interrupt path bounded:
// no clock read, no division, and one copy of at most item_bytes bytes.
fn esp_sdk_queue_try(q,item,operation) {
    if !q || !item || operation<0 || operation>2 {return 0;}
    let ps=esp32_irq_save();let capacity=esp32_load32(q);let size=esp32_load32(q+8);let head=esp32_load32(q+16);let count=esp32_load32(q+24);
    if (!operation && !count) || (operation && count==capacity) {esp32_irq_restore(ps);return 0;}
    let slot=head;if operation==1 {slot=head+count;if slot>=capacity {slot=slot-capacity;}}
    else if operation==2 {if head {slot=head-1;}else {slot=capacity-1;}esp32_store32(q+16,slot);}
    let p=q+32+slot*size;let i=0;while i<size {if operation {store8(p+i,load8(item+i));}else {store8(item+i,load8(p+i));}i=i+1;}
    if operation {esp32_store32(q+24,count+1);}else {let next=head+1;if next==capacity {next=0;}esp32_store32(q+16,next);esp32_store32(q+24,count-1);}
    esp32_irq_restore(ps);return 1;
}
fn esp_sdk_queue_op(q,item,ticks,operation) {
    if !q || !item || operation<0 || operation>2 {return 0;}
    if !ticks || esp32_load32(esp32_state()+16) {return esp_sdk_queue_try(q,item,operation);}
    let end=esp_sdk_deadline(ticks);while 1 {if esp_sdk_queue_try(q,item,operation) {return 1;}if esp_sdk_now()>=end {return 0;}esp_sdk_yield();}return 0;
}
fn esp_sdk_event_create() {return esp_sdk_calloc(1,16);}
fn esp_sdk_event_set(event,bits) {let ps=esp32_irq_save();let value=load64(event)|bits;store64(event,value);esp32_irq_restore(ps);return value;}
fn esp_sdk_event_clear(event,bits) {let ps=esp32_irq_save();let value=load64(event);store64(event,value&~bits);esp32_irq_restore(ps);return value;}
fn esp_sdk_event_wait(event,bits,clear,all,ticks) {
    let end=esp_sdk_deadline(ticks);while 1 {let ps=esp32_irq_save();let value=load64(event);let match=value&bits;
        if (all && match==bits) || (!all && match) {if clear {store64(event,value&~bits);}esp32_irq_restore(ps);return value;}esp32_irq_restore(ps);
        if !ticks || esp_sdk_now()>=end || esp32_load32(esp32_state()+16) {return value;}esp_sdk_yield();
    }return 0;
}
