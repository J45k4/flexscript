fn check_distinct_append(n,mask,begin,witness,used,earlier,retained) {
    let first=begin;
    while first<n && !((mask>>first)&1) {first=first+1;}
    if first>witness {return 1;}
    let i=0;
    while i<n {
        let flag=0x82|((mask>>i)&1);
        if i==retained {flag=flag|4;}
        store8(io_flags+i,flag);
        let entry=700+i;
        if i==earlier {entry=retained*16;}
        store64(io_work+i*8,entry);
        i=i+1;
    }
    let result=io_enqueue_preserves_worklist_entry(begin*16,n*16,used,witness*16,earlier,retained*16);
    let appended=first!=retained;
    if result!=used+appended {return 2;}
    i=0;
    while i<n {
        let flag=0x82|((mask>>i)&1);
        if i==retained || i==first {flag=flag|4;}
        if load8(io_flags+i)!=flag {return 3;}
        let entry=700+i;
        if i==earlier {entry=retained*16;}
        if i==used && appended {entry=first*16;}
        if load64(io_work+i*8)!=entry {return 4;}
        i=i+1;
    }
    return 0;
}

fn main() {
    io_flags=alloc(8);
    io_work=alloc(64);
    if io_flags<=0 || io_work<=0 {return 1;}
    let n=2;
    while n<=8 {
        let mask=1;
        while mask<(1<<n) {
            let witness=n-1;
            while !((mask>>witness)&1) {witness=witness-1;}
            let begin=0;
            while begin<=witness {
                let retained=0;
                while retained<n {
                    if (mask>>retained)&1 {
                        let bad=check_distinct_append(n,mask,begin,witness,1,0,retained);
                        if bad {return bad;}
                        bad=check_distinct_append(n,mask,begin,witness,n-1,n-2,retained);
                        if bad {return bad;}
                    }
                    retained=retained+1;
                }
                begin=begin+1;
            }
            mask=mask+1;
        }
        n=n+1;
    }
    return 0;
}
