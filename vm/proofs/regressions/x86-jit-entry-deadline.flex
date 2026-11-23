fn check_entry(code,status,entry_error,deadline) {
    vm_error=entry_error;vm_deadline=deadline;
    vm_local_memory=4096;vm_local_base=56;vm_fuel=1000;
    let offset=0;
    while offset<=40 {
        store64(vm_jit_context+offset,100+offset);
        offset=offset+8;
    }
    let ready=code && status>=0 && !entry_error && deadline>12345;
    let error=entry_error;
    if code && (status<0 || (!entry_error && deadline<=12345)) {error=8;}
    if vm_jit_prepare_entry(code,status)!=ready || vm_error!=error {return 0;}
    if load64(vm_time)!=12 || load64(vm_time+8)!=345678901 || load64(vm_jit_context+40)!=140 {return 0;}
    if ready {
        return load64(vm_jit_context)==vm_local_memory+vm_local_base &&
            load64(vm_jit_context+8)==vm_fuel && load64(vm_jit_context+16)==0 &&
            load64(vm_jit_context+24)==0 && load64(vm_jit_context+32)==deadline;
    }
    offset=0;
    while offset<40 {
        if load64(vm_jit_context+offset)!=100+offset {return 0;}
        offset=offset+8;
    }
    return 1;
}

fn main() {
    vm_time=alloc(16);vm_jit_context=alloc(48);
    if vm_time<=0 || vm_jit_context<=0 {return 1;}
    store64(vm_time,12);store64(vm_time+8,345678901);
    let code=0;
    while code<=1 {
        let status=-1;
        while status<=0 {
            let deadline=12344;
            while deadline<=12346 {
                if !check_entry(code,status,0,deadline) || !check_entry(code,status,5,deadline) {return 2;}
                deadline=deadline+1;
            }
            status=status+1;
        }
        code=code+1;
    }
    vm_time=0;vm_error=0;
    if vm_now_after_clock(-1)!=0 || vm_error!=8 {return 3;}
    return 0;
}
