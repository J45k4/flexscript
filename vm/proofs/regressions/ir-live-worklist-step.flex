fn first_live(mask,start,end) {
    while start<end && !((mask>>start)&1) {start=start+1;}
    return start;
}

fn check_step(n,mask,pc,target,initial,op,marks,witness) {
    let read=initial-1;
    let branch=first_live(mask,target,n);
    let fall=first_live(mask,pc+1,n);
    let i=0;
    while i<n {
        let flag=0x82|((mask>>i)&1);
        if (marks&1) && i==branch || (marks&2) && i==fall {flag=flag|4;}
        store8(io_flags+i,flag);
        store8(expected_flags+i,flag);
        let entry=700+i;
        if i==read {entry=pc*16;}
        store64(io_work+i*8,entry);
        store64(expected_work+i*8,entry);
        i=i+1;
    }
    store64(io_code+pc*16,op);
    store64(io_code+pc*16+8,target*16);
    let used=initial;
    if !(load8(expected_flags+branch)&4) {
        store8(expected_flags+branch,load8(expected_flags+branch)|4);
        store64(expected_work+used*8,branch*16);
        used=used+1;
    }
    if !(load8(expected_flags+fall)&4) {
        store8(expected_flags+fall,load8(expected_flags+fall)|4);
        store64(expected_work+used*8,fall*16);
        used=used+1;
    }
    let result=io_reach_conditional_step(read,initial,n*16,pc*16,target*16,witness*16,witness*16);
    if result!=used {return 2;}
    i=0;
    while i<n {
        if load8(io_flags+i)!=load8(expected_flags+i) {return 3;}
        if load64(io_work+i*8)!=load64(expected_work+i*8) {return 4;}
        i=i+1;
    }
    return 0;
}

fn main() {
    io_flags=alloc(8);
    io_work=alloc(64);
    io_code=alloc(128);
    expected_flags=alloc(8);
    expected_work=alloc(64);
    if io_flags<=0 || io_work<=0 || io_code<=0 || expected_flags<=0 || expected_work<=0 {return 1;}
    let n=3;
    while n<=8 {
        let mask=1;
        while mask<(1<<n) {
            let witness=n-1;
            while !((mask>>witness)&1) {witness=witness-1;}
            let pc=0;
            while pc<witness {
                let target=0;
                while target<=witness {
                    let marks=0;
                    while marks<4 {
                        let status=check_step(n,mask,pc,target,1,11,marks,witness);
                        if status {return status;}
                        status=check_step(n,mask,pc,target,n-2,12,marks,witness);
                        if status {return status;}
                        marks=marks+1;
                    }
                    target=target+1;
                }
                pc=pc+1;
            }
            mask=mask+1;
        }
        n=n+1;
    }
    return 0;
}
