fn copy_production_window(size) {
    // Production compaction copy loop.
}

fn initialize(n,mask,call,callee,index) {
    let i=0;
    while i<n {
        store8(io_flags+i,(mask>>i)&1);
        store64(io_code+i*16,1);
        store64(io_code+i*16+8,i+100);
        store64(output+i*16,33);
        store64(output+i*16+8,44);
        i=i+1;
    }
    store64(io_code+callee*16,18);
    store64(io_code+callee*16+8,3);
    store64(io_code+call*16,8);
    store64(io_code+call*16+8,index);
    let entry=functions+index*32;
    store64(entry+16,callee*16);
    store64(entry+24,2);
    return 0;
}

fn rank_offset(mask,i) {
    let offset=0;
    let j=0;
    while j<i {
        if (mask>>j)&1 {offset=offset+16;}
        j=j+1;
    }
    return offset;
}

fn check_scan_case(n,mask,call,callee,index) {
    initialize(n,mask,call,callee,index);
    // Seed every map word so an omitted scan write cannot pass by accident.
    let map_index=0;
    while map_index<=n {
        store64(io_map+map_index*8,-1);
        map_index=map_index+1;
    }
    let size=rank_offset(mask,n);
    let at=rank_offset(mask,call);
    let header=rank_offset(mask,callee);
    vm_pc=-1;
    vm_fuel=5;
    vm_steps=7;
    vm_depth=3;
    vm_error=0;
    output_size=n*16;
    let fetched=0;
    if callee<call {
        fetched=scan_relocate_and_fetch_selected_call(n,callee,call,index,2,3);
    }else {
        fetched=scan_relocate_and_fetch_call_before_callee(n,callee,call,index,2,3);
    }
    if fetched!=1 {return 2;}
    if vm_pc!=at+16 || vm_fuel!=4 || vm_steps!=8 || vm_error || vm_depth!=3 || output_size!=size {return 3;}
    let entry=functions+index*32;
    if load64(entry+16)!=header || load64(entry+24)!=2 {return 4;}
    if load64(output+at)!=8 || load64(output+at+8)!=index ||
        load64(output+header)!=18 || load64(output+header+8)!=3 {return 5;}
    let slot=0;
    while slot<n {
        if load64(io_map+slot*8)!=rank_offset(mask,slot) {return 6;}
        slot=slot+1;
    }
    if load64(io_map+n*8)!=size {return 7;}
    let chosen=output;
    output=reference_output;
    copy_production_window(n*16);
    output=chosen;
    if load64(output+at)!=load64(reference_output+at) ||
        load64(output+at+8)!=load64(reference_output+at+8) ||
        load64(output+header)!=load64(reference_output+header) ||
        load64(output+header+8)!=load64(reference_output+header+8) {return 8;}
    return 0;
}
fn main() {
    output=alloc(112);
    reference_output=alloc(112);
    io_code=alloc(112);
    io_flags=alloc(7);
    io_map=alloc(64);
    function_count=5;
    functions=alloc(function_count*32);
    if output<=0 || reference_output<=0 || io_code<=0 || io_flags<=0 || io_map<=0 || functions<=0 {return 1;}
    let n=2;
    while n<=7 {
        let mask=0;
        while mask<(1<<n) {
            let call=0;
            while call<n {
                let callee=0;
                while callee<n {
                    if call!=callee && ((mask>>call)&1) && ((mask>>callee)&1) {
                        let bad=check_scan_case(n,mask,call,callee,0);
                        if bad {return bad;}
                        bad=check_scan_case(n,mask,call,callee,function_count-1);
                        if bad {return bad;}
                    }
                    callee=callee+1;
                }
                call=call+1;
            }
            mask=mask+1;
        }
        n=n+1;
    }
    return 0;
}