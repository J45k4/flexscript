// A reusable, 16-byte aligned arena for SDK C allocations. This arena is
// separate from Flexscript's native bump heap; no libc/RTOS allocator needed.
global esp_sdk_begin=0;
global esp_sdk_end=0;
global esp_sdk_allocated=0;
global esp_sdk_rover=0;
fn esp_sdk_heap_init(base,size) {
    if base<0x3ffc8000 || (base&15) || size<64 || (size&15) || base+size>0x3ffe0000 {return -22;}
    if esp_sdk_begin {return -16;}esp_sdk_begin=base;esp_sdk_end=base+size;esp_sdk_allocated=0;esp_sdk_rover=base;
    esp32_store32(base,size-16);esp32_store32(base+4,0);esp32_store32(base+8,0);esp32_store32(base+12,0x48454150);
    let end=base+size-16;esp32_store32(end,17);esp32_store32(end+4,size-16);esp32_store32(end+8,0);esp32_store32(end+12,0x48454150);return 0;
}
fn esp_sdk_header(p) {
    if p<esp_sdk_begin+16 || p>=esp_sdk_end-16 || (p&15) {return 0;}let h=p-16;
    if esp32_load32(h+12)!=0x48454150 || !(esp32_load32(h)&1) {return 0;}return h;
}
fn esp_sdk_malloc(size) {
    if size<=0 || size>0x18000 || !esp_sdk_begin {return 0;}let need=(size+31)&~15;let ps=esp32_irq_save();let h=esp_sdk_rover;let start=h;
    // The cursor always names a block header. Free resets it to the final
    // coalesced block, so no operation can leave it inside a merged extent.
    let searched=0;while !searched || h!=start {searched=1;
        let raw=esp32_load32(h);let span=raw&~15;
        if span<16 || h+span>esp_sdk_end-16 || esp32_load32(h+12)!=0x48454150 {esp32_irq_restore(ps);return 0;}
        if !(raw&1) && span>=need {
            if span-need>=32 {let next=h+need;esp32_store32(next,span-need);esp32_store32(next+4,need);esp32_store32(next+8,0);esp32_store32(next+12,0x48454150);esp32_store32(h+span+4,span-need);span=need;}
            esp32_store32(h,span|1);esp32_store32(h+8,size);esp_sdk_allocated=esp_sdk_allocated+span;esp_sdk_rover=h+span;if esp_sdk_rover>=esp_sdk_end-16 {esp_sdk_rover=esp_sdk_begin;}esp32_irq_restore(ps);return h+16;
        }h=h+span;if h>=esp_sdk_end-16 {h=esp_sdk_begin;}
    }esp32_irq_restore(ps);return 0;
}
fn esp_sdk_free(p) {
    if !p {return 0;}let ps=esp32_irq_save();let h=esp_sdk_header(p);if !h {esp32_irq_restore(ps);return -22;}
    let span=esp32_load32(h)&~15;esp_sdk_allocated=esp_sdk_allocated-span;esp32_store32(h,span);esp32_store32(h+8,0);
    let next=h+span;if !(esp32_load32(next)&1) {let more=esp32_load32(next)&~15;esp32_store32(next+12,0);span=span+more;esp32_store32(h,span);esp32_store32(h+span+4,span);}
    let before=esp32_load32(h+4);if before && !(esp32_load32(h-before)&1) {esp32_store32(h+12,0);h=h-before;span=span+before;esp32_store32(h,span);esp32_store32(h+span+4,span);}
    esp_sdk_rover=h;esp32_irq_restore(ps);return 0;
}
fn esp_sdk_calloc(n,size) {
    if n<=0 || size<=0 || n>0x18000/size {return 0;}let total=n*size;let p=esp_sdk_malloc(total);if p {let i=0;while i<total {store8(p+i,0);i=i+1;}}return p;
}
fn esp_sdk_realloc(p,size) {
    if !p {return esp_sdk_malloc(size);}if !size {esp_sdk_free(p);return 0;}let h=esp_sdk_header(p);if !h {return 0;}let count=esp32_load32(h+8);let out=esp_sdk_malloc(size);if !out {return 0;}esp_sdk_heap_tag(out,(esp32_load32(h)>>1)&7);if count>size {count=size;}let i=0;while i<count {store8(out+i,load8(p+i));i=i+1;}esp_sdk_free(p);return out;
}
fn esp_sdk_heap_free() {if !esp_sdk_begin {return 0;}return esp_sdk_end-esp_sdk_begin-16-esp_sdk_allocated;}

// Explicit lifecycle domains use the otherwise unused low header bits. Native
// application allocations stay untagged; callers must quiesce a domain before
// releasing it. This never resets the arena or touches another domain.
fn esp_sdk_heap_tag(pointer,owner) {
    if !pointer {return 0;}if owner<0 || owner>7 {return 0;}let ps=esp32_irq_save();let h=esp_sdk_header(pointer);
    if !h {esp32_irq_restore(ps);return 0;}esp32_store32(h,(esp32_load32(h)&~14)|(owner<<1));esp32_irq_restore(ps);return pointer;
}
fn esp_sdk_heap_owner(pointer) {let h=esp_sdk_header(pointer);if !h {return -22;}return (esp32_load32(h)>>1)&7;}
fn esp_sdk_heap_release_owner(owner) {
    if owner<1 || owner>7 {return -22;}let released=0;let again=1;
    while again {again=0;let ps=esp32_irq_save();let h=esp_sdk_begin;
        while h && h<esp_sdk_end-16 {let header_word=esp32_load32(h);let block_size=header_word&~15;
            if block_size<16 || h+block_size>esp_sdk_end-16 || esp32_load32(h+12)!=0x48454150 {esp32_irq_restore(ps);return -22;}
            if (header_word&1) && ((header_word>>1)&7)==owner {esp_sdk_free(h+16);released=released+1;again=1;h=0;}else {h=h+block_size;}
        }esp32_irq_restore(ps);
    }return released;
}
