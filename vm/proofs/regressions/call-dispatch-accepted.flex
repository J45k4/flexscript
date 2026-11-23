fn check_dispatched_frame(at,callee,index,arity,slots,depth,spare) {
    let record=functions+index*32;
    let floor=depth*16;
    let args=floor+spare;
    store64(output+at,8);
    store64(output+at+8,index);
    store64(output+callee,18);
    store64(output+callee+8,slots);
    store64(record+16,callee);
    store64(record+24,arity);
    let word=0;
    while word<12 {
        store64(vm_stack+word*8,100+word);
        store64(vm_local_memory+word*8,200+word);
        store64(vm_frames+word*8,300+word);
        word=word+1;
    }
    if depth {store64(vm_frames+24,floor);}
    output_size=32;
    vm_pc=at;
    vm_fuel=13;
    vm_steps=17;
    vm_error=0;
    vm_depth=depth;
    vm_sp=args+arity*8;
    vm_local_base=8;
    vm_local_top=24;
    if vm_dispatch_accepted_linked_call(at,index,callee,arity,slots)!=1 {return 2;}
    if vm_error || vm_fuel!=12 || vm_steps!=18 ||
        vm_pc!=callee+16 || vm_depth!=depth+1 || vm_sp!=args ||
        vm_local_base!=24 || vm_local_top!=24+slots*8 {return 3;}
    let frame=vm_frames+depth*40;
    if load64(frame)!=at+16 || load64(frame+8)!=8 || load64(frame+16)!=24 ||
        load64(frame+24)!=args || load64(frame+32)!=index {return 4;}
    if depth && (load64(vm_frames)!=300 || load64(vm_frames+8)!=301 ||
        load64(vm_frames+16)!=302 || load64(vm_frames+24)!=floor ||
        load64(vm_frames+32)!=304) {return 5;}
    word=0;
    while word<slots {
        let expected=0;
        if word<arity {expected=100+args/8+word;}
        if load64(vm_local_memory+24+word*8)!=expected {return 6;}
        word=word+1;
    }
    if load64(vm_local_memory+16)!=202 || load64(vm_local_memory+24+slots*8)!=203+slots {return 7;}
    return 0;
}

fn main() {
    output=alloc(32);
    functions=alloc(64);
    vm_stack=alloc(96);
    vm_local_memory=alloc(96);
    vm_frames=alloc(96);
    function_count=2;
    if output<=0 || functions<=0 || vm_stack<=0 || vm_local_memory<=0 || vm_frames<=0 {return 1;}
    let depth=0;
    while depth<2 {
        let at=0;
        while at<32 {
            let index=0;
            while index<2 {
                let arity=0;
                while arity<=4 {
                    let slots=arity;
                    while slots<=7 {
                        let bad=check_dispatched_frame(at,16-at,index,arity,slots,depth,0);
                        if bad {return bad;}
                        bad=check_dispatched_frame(at,16-at,index,arity,slots,depth,8);
                        if bad {return bad;}
                        slots=slots+1;
                    }
                    arity=arity+1;
                }
                index=index+1;
            }
            at=at+16;
        }
        depth=depth+1;
    }
    return 0;
}
