// Check every live/dead pattern and selected record in tables with one to six records.
fn check_relocated_calls(n,mask,watch) {
    let i=0;
    call_count=n;
    output_size=99;
    while i<n {
        store64(calls+i*32,100+i);
        store64(calls+i*32+8,200+i);
        store64(calls+i*32+16,i*16+8);
        store64(calls+i*32+24,300+i);
        store8(io_flags+i,(mask>>i)&1);
        store64(io_map+i*8,(n-1-i)*16);
        i=i+1;
    }
    let result=io_relocate_observes_original_call_pc(n,watch);
    let used=0;
    i=0;
    while i<n {
        if (mask>>i)&1 {
            if load64(calls+used*32)!=100+i || load64(calls+used*32+8)!=200+i ||
                load64(calls+used*32+16)!=(n-1-i)*16+8 || load64(calls+used*32+24)!=300+i {return 1;}
            used=used+1;
        }
        i=i+1;
    }
    if output_size!=99 || call_count!=n || used!=result {return 2;}
    return 0;
}
fn main() {
    calls=alloc(192);
    io_flags=alloc(6);
    io_map=alloc(56);
    if calls<=0 || io_flags<=0 || io_map<=0 {return 3;}
    let n=1;
    while n<=6 {
        let mask=0;
        while mask<(1<<n) {
            let watch=0;
            while watch<n {
                let problem=check_relocated_calls(n,mask,watch);
                if problem {return problem;}
                watch=watch+1;
            }
            mask=mask+1;
        }
        n=n+1;
    }
    return 0;
}
