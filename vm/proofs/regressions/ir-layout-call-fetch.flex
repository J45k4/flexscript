fn copy_production_window(size) {
    // Production compaction copy loop.
    return 0;
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

fn check_case(n,mask,call,callee,index,relocate) {
    initialize(n,mask,call,callee,index);
    let size=io_build_layout(n);
    let at=rank_offset(mask,call);
    let header=rank_offset(mask,callee);
    if at!=io_compacted_offset(call*16) || header!=io_compacted_offset(callee*16) ||
        size!=rank_offset(mask,n) {return 2;}
    let entry=functions+index*32;
    if !relocate {
        io_write_compacted_instruction(callee*16,header);
        io_relocate_function(entry,callee*16);
    }
    vm_pc=at;
    vm_fuel=5;
    vm_steps=7;
    vm_depth=3;
    vm_error=0;
    output_size=n*16;
    let result=0;
    if relocate {
        if callee<call {
            result=optimizer_compacted_call_to_vm_metadata(call*16,callee*16,at,header,size,index,2,3);
        }else {
            result=optimizer_compacted_call_before_callee(call*16,callee*16,at,header,size,index,2,3);
        }
    }else {
        result=optimizer_copy_call_to_ready_metadata(call*16,at,size,index,header,2,3);
    }
    if result!=1 || vm_error!=0 || vm_depth!=3 {return 3;}
    if vm_pc!=at+16 || vm_fuel!=4 || vm_steps!=8 || output_size!=size {return 4;}
    if load64(output+at)!=8 || load64(output+at+8)!=index ||
        load64(output+header)!=18 || load64(output+header+8)!=3 {return 5;}
    if load64(entry+16)!=header || load64(entry+24)!=2 {return 6;}
    let chosen=output;
    output=reference_output;
    copy_production_window(n*16);
    output=chosen;
    if load64(output+at)!=load64(reference_output+at) ||
        load64(output+at+8)!=load64(reference_output+at+8) ||
        load64(output+header)!=load64(reference_output+header) ||
        load64(output+header+8)!=load64(reference_output+header+8) {return 7;}
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
                        let bad=check_case(n,mask,call,callee,0,0);
                        if bad {return bad;}
                        bad=check_case(n,mask,call,callee,function_count-1,0);
                        if bad {return bad;}
                        bad=check_case(n,mask,call,callee,0,1);
                        if bad {return bad;}
                        bad=check_case(n,mask,call,callee,function_count-1,1);
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
