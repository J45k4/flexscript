// Place native IR literals after function bodies. Ordinary writable literals
// retain per-site storage. Explicit shared mode interns identical byte strings.
global ni_literal_shared=0;
global ni_literal_entries=0;
global ni_literal_count=0;
global ni_literal_capacity=0;
global ni_literal_table=0;
global ni_literal_mask=0;
global ni_literal_refs=0;
global ni_literal_ref_count=0;
global ni_literal_ref_begin=0;
fn ni_literals_prepare() {
    let count=0;let pc=0;while pc<ni_size {if load64(ni_code+pc)==28 {count=count+1;}pc=pc+16;}
    ni_literal_capacity=count;ni_literal_count=0;ni_literal_ref_count=0;ni_literal_ref_begin=0;
    let capacity=16;while capacity<count*2 {capacity=capacity*2;}
    ni_literal_mask=capacity-1;ni_literal_table=alloc(capacity*8);
    ni_literal_entries=alloc(count*32+32);ni_literal_refs=alloc(count*16+16);
    if ni_literal_table<0 || ni_literal_entries<0 || ni_literal_refs<0 {fail("cannot allocate native literal pool");}return 0;
}
fn ni_literal_entry(arg) {
    let offset=arg&4294967295;let count=arg>>32;let hash=(offset*2654435761)&0xffffffff;
    if ni_literal_shared {hash=2166136261;let i=0;while i<count {hash=((hash^load8(vm_heap+offset+i))*16777619)&0xffffffff;i=i+1;}}
    let slot=hash&ni_literal_mask;let looking=1;
    while looking {
        let index=load64(ni_literal_table+slot*8);
        if !index {
            if ni_literal_count>=ni_literal_capacity {fail("native literal pool exceeds IR literal count");}
            index=ni_literal_count;ni_literal_count=index+1;let entry=ni_literal_entries+index*32;
            store64(entry,offset);store64(entry+8,count);store64(entry+24,hash);store64(ni_literal_table+slot*8,index+1);return index;
        }
        index=index-1;let entry=ni_literal_entries+index*32;
        if load64(entry+8)==count && load64(entry+24)==hash {
            if (!ni_literal_shared && load64(entry)==offset) || (ni_literal_shared && equal(vm_heap+offset,count,vm_heap+load64(entry),count)) {return index;}
        }slot=(slot+1)&ni_literal_mask;
    }return 0;
}
fn ni_literal_reference(arg) {
    let index=ni_literal_entry(arg);if ni_literal_ref_count>=ni_literal_capacity {fail("native literal relocation exceeds IR literal count");}
    emit(72);emit(141);emit(5);let ref=ni_literal_refs+ni_literal_ref_count*16;
    store64(ref,output_size);store64(ref+8,index);ni_literal_ref_count=ni_literal_ref_count+1;emit32(0);return 0;
}
fn ni_literals_finish() {
    let i=0;while i<ni_literal_count {
        let entry=ni_literal_entries+i*32;store64(entry+16,output_size);let at=0;
        while at<load64(entry+8) {emit(load8(vm_heap+load64(entry)+at));at=at+1;}i=i+1;
    }
    i=0;while i<ni_literal_ref_count {let ref=ni_literal_refs+i*16;let at=load64(ref);let target=load64(ni_literal_entries+load64(ref+8)*32+16);patch32(at,target-at-4);i=i+1;}return 0;
}
