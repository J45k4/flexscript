// Independent live-allocation model: validate byte patterns, nonoverlap,
// block-chain accounting, coalescing and the sentinel after every operation.
fn sh_validate(slots) {
    let h=esp_sdk_begin;let previous=0;let was_free=0;let allocated=0;let blocks=0;
    while h<esp_sdk_end-16 {
        let raw=esp32_load32(h);let span=raw&~15;let used=raw&1;
        if span<16 || h+span>esp_sdk_end-16 || esp32_load32(h+4)!=previous || esp32_load32(h+12)!=0x48454150 || blocks>=1024 {return 1;}
        if used {let found=0;let j=0;while j<32 {let p=load64(slots+j*24);if p==h+16 {if found || (p&15) || load64(slots+j*24+8)>span-16 || esp32_load32(h+8)!=load64(slots+j*24+8) {return 2;}found=1;}j=j+1;}if !found {return 3;}allocated=allocated+span;}
        else {if was_free || esp32_load32(h+8) {return 4;}}
        was_free= !used;previous=span;h=h+span;blocks=blocks+1;
    }
    if h!=esp_sdk_end-16 || esp32_load32(h)!=17 || esp32_load32(h+4)!=previous || esp32_load32(h+12)!=0x48454150 || allocated!=esp_sdk_allocated || esp_sdk_heap_free()!=esp_sdk_end-esp_sdk_begin-16-allocated {return 5;}
    let i=0;while i<32 {let p=load64(slots+i*24);if p {let size=load64(slots+i*24+8);let tag=load64(slots+i*24+16);let k=0;while k<size {if load8(p+k)!=((tag+k)&255) {return 6;}k=k+1;}
        let j=i+1;while j<32 {let q=load64(slots+j*24);if q && p<q+load64(slots+j*24+8) && q<p+size {return 7;}j=j+1;}}
        i=i+1;
    }return 0;
}
fn sh_churn() {
    let initial_free=esp_sdk_heap_free();
    let slots=alloc(768);let i=0;while i<768 {store8(slots+i,0);i=i+1;}let seed=0x12345678;i=0;
    while i<512 {
        seed=(seed*1664525+1013904223)&4294967295;let slot=slots+(seed&31)*24;let p=load64(slot);let old_size=load64(slot+8);let tag=load64(slot+16);let size=1+((seed>>16)%512);let action=(seed>>5)&3;
        if p && !action {if esp_sdk_free(p) {return 10;}store64(slot,0);}
        else {
            let q=0;if p && action==1 {q=esp_sdk_realloc(p,size);if !q {return 11;}let count=old_size;if count>size {count=size;}let j=0;while j<count {if load8(q+j)!=((tag+j)&255) {return 12;}j=j+1;}}
            else {if p && esp_sdk_free(p) {return 13;}q=esp_sdk_calloc(1,size);if !q {return 14;}let j=0;while j<size {if load8(q+j) {return 15;}j=j+1;}}
            store64(slot,q);store64(slot+8,size);tag=(seed>>8)&255;store64(slot+16,tag);let j=0;while j<size {store8(q+j,(tag+j)&255);j=j+1;}
        }
        let error=sh_validate(slots);if error {return 20+error;}i=i+1;
    }
    i=0;while i<32 {let p=load64(slots+i*24);if p && esp_sdk_free(p) {return 30;}store64(slots+i*24,0);i=i+1;}if sh_validate(slots) {return 31;}
    // Exhaustion plus separated holes exercises search wrap and split/coalesce.
    let a=esp_sdk_malloc(128);let b=esp_sdk_malloc(128);let c=esp_sdk_malloc(128);let tail=esp_sdk_malloc(esp_sdk_heap_free()-16);if !a || !b || !c || !tail || esp_sdk_malloc(1) {return 32;}
    store64(b,0x123456789abcdef0);store64(tail,0x1020304050607080);if esp_sdk_free(a) || esp_sdk_free(c) {return 33;}
    let x=esp_sdk_malloc(64);let y=esp_sdk_malloc(64);if !x || !y || x==y || load64(b)!=0x123456789abcdef0 || load64(tail)!=0x1020304050607080 {return 34;}
    if esp_sdk_free(x) || esp_sdk_free(y) || esp_sdk_free(b) || esp_sdk_free(tail) || esp_sdk_allocated || esp_sdk_heap_free()!=initial_free {return 35;}
    return 0;
}
