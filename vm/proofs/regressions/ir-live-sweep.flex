fn check_sweep(n,start,observed,sample) {
    let slot=0;
    let removed=0;
    while slot<8 {
        let flag=(sample+slot*37)&255;
        if slot==observed {flag=sample;}
        store8(io_flags+slot,flag);
        if slot>=start && slot<n && !(flag&4) {
            if flag&1 {removed=removed+1;}
            flag=flag&254;
        }
        store8(expected_flags+slot,flag);
        slot=slot+1;
    }
    ir_opt_dead=5;
    if io_reach_sweep_observed(start*16,n*16,observed*16)!=0 {return 1;}
    slot=0;
    while slot<8 {
        if load8(io_flags+slot)!=load8(expected_flags+slot) {return 2;}
        slot=slot+1;
    }
    if ir_opt_dead!=5+removed {return 3;}
    return 0;
}

fn main() {
    io_flags=alloc(8);
    expected_flags=alloc(8);
    if io_flags<=0 || expected_flags<=0 {return 1;}
    let count=1;
    while count<=8 {
        let start=0;
        while start<=count {
            let observed=0;
            while observed<count {
                let sample=0;
                while sample<256 {
                    let failure=check_sweep(count,start,observed,sample);
                    if failure {return failure;}
                    sample=sample+1;
                }
                observed=observed+1;
            }
            start=start+1;
        }
        count=count+1;
    }
    return 0;
}
