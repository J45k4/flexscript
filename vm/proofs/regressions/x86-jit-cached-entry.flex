fn check_cached_record(index,mark,calls) {
    let cache=vm_jit_cache+index*32;
    let code=65536+index*4096;
    let bytes=4096*(index+1);
    store64(cache,code);store64(cache+8,bytes);store64(cache+16,calls);store64(cache+24,mark);
    let selected=vm_jit_select_cached(index);
    if mark==2 {
        if selected {return 0;}
    }else {
        if selected!=code {return 0;}
        calls=calls+1;
    }
    vm_jit_write_context(cache);
    return load64(cache)==code && load64(cache+8)==bytes && load64(cache+16)==calls && load64(cache+24)==mark &&
        load64(vm_jit_context)==vm_local_memory+vm_local_base && load64(vm_jit_context+8)==vm_fuel &&
        load64(vm_jit_context+16)==0 && load64(vm_jit_context+24)==0 &&
        load64(vm_jit_context+32)==vm_deadline && load64(vm_jit_context+40)==777;
}

fn check_cached_boundary(index,mark,status,prior_error,deadline) {
    let cache=vm_jit_cache+index*32;
    let code=65536+index*4096;
    store64(cache,code);store64(cache+8,4096);store64(cache+16,12);store64(cache+24,mark);
    vm_error=prior_error;vm_deadline=deadline;
    let offset=0;
    while offset<40 {store64(vm_jit_context+offset,600+offset);offset=offset+8;}
    let expected=0;let error=prior_error;let calls=12;
    if mark!=2 {
        calls=13;
        if status<0 || (!prior_error && deadline<=12345) {error=8;}
        if status>=0 && !prior_error && deadline>12345 {expected=code;}
    }
    if vm_jit_cached_entry(index,status)!=expected || vm_error!=error {return 0;}
    if load64(cache)!=code || load64(cache+8)!=4096 || load64(cache+16)!=calls || load64(cache+24)!=mark ||
       load64(vm_jit_context+40)!=777 {return 0;}
    if expected {
        return load64(vm_jit_context)==vm_local_memory+vm_local_base && load64(vm_jit_context+8)==vm_fuel &&
            load64(vm_jit_context+16)==0 && load64(vm_jit_context+24)==0 && load64(vm_jit_context+32)==deadline;
    }
    offset=0;
    while offset<40 {
        if load64(vm_jit_context+offset)!=600+offset {return 0;}
        offset=offset+8;
    }
    return 1;
}

fn test_cached_boundary(index,mark) {
    let status=-1;
    while status<=0 {
        let deadline=12344;
        while deadline<=12346 {
            if !check_cached_boundary(index,mark,status,0,deadline) ||
               !check_cached_boundary(index,mark,status,5,deadline) {return 0;}
            deadline=deadline+1;
        }
        status=status+1;
    }
    return 1;
}

fn main() {
    vm_jit_cache=alloc(256);vm_jit_context=alloc(48);vm_time=alloc(16);
    if vm_jit_cache<=0 || vm_jit_context<=0 || vm_time<=0 {return 1;}
    vm_jit_threshold=1;vm_local_memory=4096;vm_local_base=64;vm_fuel=100;vm_deadline=1000;
    store64(vm_time,12);store64(vm_time+8,345678901);
    store64(vm_jit_context+40,777);
    let index=0;
    while index<8 {
        let mark=0;
        while mark<4 {
            if !check_cached_record(index,mark,-1) ||
               !check_cached_record(index,mark,0) ||
               !check_cached_record(index,mark,0x7fffffffffffffff) {return 2;}
            if !test_cached_boundary(index,mark) {return 3;}
            mark=mark+1;
        }
        index=index+7;
    }
    return 0;
}
