fn run_map_case(map_count,observed) {
    let offsets=alloc(8193*8);
    vm_jit_map=alloc(8193*8);
    if offsets<=0 || vm_jit_map<=0 {return 1;}
    let start=96;
    let end=start+map_count*16;
    let slot=0;
    while slot<8193 {
        store64(vm_jit_map+slot*8,-333);
        store64(offsets+slot*8,17+slot*233);
        slot=slot+1;
    }
    if jit_record_map_prefix(start,end,map_count,offsets,observed)!=map_count {return 2;}
    slot=1;
    while slot<map_count {
        if load64(vm_jit_map+slot*8)!=17+slot*233 {return 3;}
        slot=slot+1;
    }
    if load64(vm_jit_map)!=-333 || load64(vm_jit_map+map_count*8)!=-333 ||
        load64(vm_jit_map+8192*8)!=-333 {return 4;}
    if syscall(11,vm_jit_map,8193*8,0,0,0,0)<0 ||
        syscall(11,offsets,8193*8,0,0,0,0)<0 {return 5;}
    return 0;
}

fn main() {
    let r=run_map_case(1,1);
    if r {return r;}
    r=run_map_case(2,1);
    if r {return r;}
    return run_map_case(8192,8191);
}
