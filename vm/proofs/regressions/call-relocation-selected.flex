fn initial_pc(i,bad) {
    if i==bad {return -1;}
    return i*16+8;
}
fn map_value(n,i,wide) {
    if wide {return 0x7ffffffffffffff0+i*16;}
    return (n-1-i)*16;
}
fn init_records(table,n,bad) {
    let i=0;
    while i<n {
        store64(table+i*32,100+i);
        store64(table+i*32+8,200+i);
        store64(table+i*32+16,initial_pc(i,bad));
        store64(table+i*32+24,300+i);
        i=i+1;
    }
    return 0;
}
fn check_case(n,mask,watch,bad,wide,byte) {
    let projected_calls=calls;
    init_records(calls,n,bad);
    init_records(expected_calls,n,bad);
    output_size=99;
    call_count=n;
    let i=0;
    let rank=0;
    let used=0;
    while i<n {
        let live=(mask>>i)&1;
        store8(io_flags+i,live);
        store64(io_map+i*8,map_value(n,i,wide));
        if live {
            if i<watch {rank=rank+1;}
            used=used+1;
        }
        i=i+1;
    }
    let projected=io_relocate_selected_live_pc_byte(n,watch,watch*16,map_value(n,watch,wide),byte);
    if calls!=projected_calls || call_count!=n || output_size!=99 {return 2;}
    calls=expected_calls;
    let actual=io_relocate_guarded_calls(n);
    calls=projected_calls;
    if call_count!=n || output_size!=99 {return 3;}
    if bad>=0 {
        if actual!= -1 || projected!= -1 {return 4;}
    }else {
        if actual!=used || projected!=rank {return 5;}
        let at=calls+rank*32;
        if load64(at)!=100+watch || load64(at+8)!=200+watch ||
            load64(at+16)!=map_value(n,watch,wide)+8 || load64(at+24)!=300+watch {return 6;}
    }
    i=0;
    while i<n*32 {
        if load8(calls+i)!=load8(expected_calls+i) {return 7;}
        i=i+1;
    }
    return 0;
}
fn main() {
    calls=alloc(192);
    expected_calls=alloc(192);
    io_flags=alloc(6);
    io_map=alloc(56);
    if calls<=0 || expected_calls<=0 || io_flags<=0 || io_map<=0 {return 1;}
    let n=1;
    while n<=6 {
        let mask=0;
        while mask<(1<<n) {
            let watch=0;
            while watch<n {
                if (mask>>watch)&1 {
                    let bad=-1;
                    while bad<n {
                        if bad!=watch {
                            let wide=0;
                            while wide<2 {
                                let byte=0;
                                while byte<8 {
                                    let error=check_case(n,mask,watch,bad,wide,byte);
                                    if error {return error;}
                                    byte=byte+1;
                                }
                                wide=wide+1;
                            }
                        }
                        bad=bad+1;
                    }
                }
                watch=watch+1;
            }
            mask=mask+1;
        }
        n=n+1;
    }
    return 0;
}
