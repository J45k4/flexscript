fn check_live_pair(n,mask,first,later) {
    let i=0;
    while i<n {
        store8(io_flags+i,((mask>>i)&1)|(i*16));
        store64(io_map+i*8,-1);
        i=i+1;
    }
    store64(io_map+n*8,-1);
    let size=io_build_layout_ordered_live_pair(n,first,later);
    let at=0;
    i=0;
    while i<n {
        if load64(io_map+i*8)!=at {return 3;}
        if load8(io_flags+i)!=(((mask>>i)&1)|(i*16)) {return 4;}
        if (mask>>i)&1 {at=at+16;}
        i=i+1;
    }
    if size!=at || load64(io_map+n*8)!=at {return 5;}
    if load64(io_map+first*8)>=load64(io_map+later*8) || load64(io_map+later*8)>size-16 {return 6;}
    return 0;
}
fn main() {
    io_flags=alloc(10);
    io_map=alloc(88);
    if io_flags<=0 || io_map<=0 {return 1;}
    let n=2;
    while n<=10 {
        let mask=0;
        while mask<(1<<n) {
            let first=0;
            while first<n {
                let later=first+1;
                while later<n {
                    if ((mask>>first)&1) && ((mask>>later)&1) {
                        let failed=check_live_pair(n,mask,first,later);
                        if failed {return failed;}
                    }
                    later=later+1;
                }
                first=first+1;
            }
            mask=mask+1;
        }
        n=n+1;
    }
    return 0;
}
