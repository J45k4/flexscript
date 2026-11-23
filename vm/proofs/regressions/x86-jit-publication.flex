fn copy_check(code,size,observed) {
    output_size=size;
    let i=0;
    while i<size+8 {
        store8(output+i,(i*73+(i>>8))&255);
        store8(code+i,42);
        i=i+1;
    }
    if vm_jit_copy_published_bytes(code,observed)!=size {return 2;}
    i=0;
    while i<size+8 {
        let v=(i*73+(i>>8))&255;
        if load8(output+i)!=v {return 3;}
        if i>=size {v=42;}
        if load8(code+i)!=v {return 4;}
        i=i+1;
    }
    return 0;
}
fn test_copy() {
    output=alloc(1048584);
    let code=alloc(1048584);
    if output<=0 || code<=0 {return 1;}
    let page=1;
    while page<=32 {
        let extent=page*4096;
        let status=copy_check(code,extent-1,0);
        if status {return status;}
        status=copy_check(code,extent,extent/2);
        if status {return status;}
        status=copy_check(code,extent+1,extent);
        if status {return status;}
        page=page+1;
    }
    return copy_check(code,1048576,1048575);
}

fn test_extent(size,used) {
    let expected=(size+4095)&(~4095);
    if expected>1048576 || used+expected>16777216 {expected=0;}
    return vm_jit_admitted_publication_extent(size,used)==expected;
}
fn test_extents() {
    let page=1;
    while page<=16384 {
        let size=page<<12;
        let used=16777216-size;
        if used<0 {used=0;}
        if !test_extent(size-1,used) || !test_extent(size,used) {return 2;}
        if size<67108864 && !test_extent(size+1,used) {return 2;}
        if !test_extent(size,used+1) || !test_extent(size,0) || !test_extent(size,16777216) {return 2;}
        page=page+1;
    }
    if !test_extent(1,0) || !test_extent(1,16773120) || !test_extent(1,16773121) {return 2;}
    return 0;
}

fn reset_publication(staging,size,used) {
    output=staging;output_size=size;vm_mode=0;
    vm_jit_bytes=used;vm_jit_compilations=700;
    store64(vm_jit_cache,61);store64(vm_jit_cache+8,62);
    store64(vm_jit_cache+16,63);store64(vm_jit_cache+24,64);
}

fn publication_state_matches(pointer,extent,used) {
    if output!=16777217 || output_size!=77 || vm_mode!=1 {return 0;}
    if load64(vm_jit_cache+16)!=63 || load64(vm_jit_cache+24)!=64 {return 0;}
    if !pointer {
        return load64(vm_jit_cache)==61 && load64(vm_jit_cache+8)==62 &&
            vm_jit_bytes==used && vm_jit_compilations==700;
    }
    return load64(vm_jit_cache)==pointer && load64(vm_jit_cache+8)==extent &&
        vm_jit_bytes==used+extent && vm_jit_compilations==701;
}

fn check_cache_outcome(size,used,mapped,protection,extent,admitted) {
    reset_publication(0,size,used);
    let expected=0;
    if admitted && mapped>0 && protection>=0 {expected=mapped;}
    let pointer=vm_jit_publication_outcome(0,16777217,77,mapped,protection);
    return pointer==expected && publication_state_matches(expected,extent,used);
}

fn check_publication_handoff(staging,code,size,protection) {
    let extent=(size+4095)&(~4095);
    let used=16777216-extent;
    reset_publication(staging,size,used);
    let i=0;
    while i<size+1 {
        let value=(i*73+(i>>8))&255;
        store8(staging+i,value);store8(code+i,value^255);
        i=i+1;
    }
    let expected=code;
    if protection<0 {expected=0;}
    let result=vm_jit_publish_admitted_image(0,16777217,77,code,protection,size-1);
    if result!=expected || !publication_state_matches(expected,extent,used) {return 0;}
    i=0;
    while i<size {
        let value=(i*73+(i>>8))&255;
        if load8(staging+i)!=value || load8(code+i)!=value {return 0;}
        i=i+1;
    }
    let final=(size*73+(size>>8))&255;
    return load8(staging+size)==final && load8(code+size)==(final^255);
}

fn test_publication() {
    vm_jit_cache=alloc(32);
    let staging=alloc(8192);
    let code=alloc(8192);
    if vm_jit_cache<=0 || staging<=0 || code<=0 {return 19;}
    let protection=-1;
    while protection<=1 {
        let mapped=-1;
        while mapped<=1 {
            if !check_cache_outcome(17,16773120,mapped,protection,4096,1) ||
               !check_cache_outcome(17,16773121,mapped,protection,4096,0) ||
               !check_cache_outcome(1048576,0,mapped,protection,1048576,1) ||
               !check_cache_outcome(1048577,0,mapped,protection,0,0) {return 20;}
            mapped=mapped+1;
        }
        if !check_publication_handoff(staging,code,1,protection) ||
           !check_publication_handoff(staging,code,4095,protection) ||
           !check_publication_handoff(staging,code,4096,protection) ||
           !check_publication_handoff(staging,code,4097,protection) {return 21;}
        protection=protection+1;
    }
    return 0;
}

fn main() {
    let status=test_extents();
    if status {return status;}
    status=test_copy();
    if status {return status+8;}
    return test_publication();
}
