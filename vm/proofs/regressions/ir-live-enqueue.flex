fn check_queue_case(n,mask,begin,observed,used,marked,retained) {
    let first=begin;
    while first<n && !((mask>>first)&1) {first=first+1;}
    if first>observed {return 1;}
    let other_mark=(begin+observed+retained+used)&1;
    let slot=0;
    while slot<n {
        let flags=0x82|((mask>>slot)&1);
        if marked && slot==first || other_mark && slot==retained && slot!=first {flags=flags|4;}
        store8(io_flags+slot,flags);
        store64(io_work+slot*8,700+slot);
        slot=slot+1;
    }
    let result=io_enqueue_preserves_observed_flag(begin*16,n*16,used,observed*16,retained*16);
    if marked && result!=used {return 2;}
    if !marked && result!=used+1 {return 3;}
    slot=0;
    while slot<n {
        let expected=0x82|((mask>>slot)&1);
        if slot==first || other_mark && slot==retained {expected=expected|4;}
        if load8(io_flags+slot)!=expected {return 4;}
        let work=700+slot;
        if slot==used && !marked {work=first*16;}
        if load64(io_work+slot*8)!=work {return 5;}
        slot=slot+1;
    }
    return 0;
}

fn main() {
    io_flags=alloc(8);
    io_work=alloc(64);
    if io_flags<=0 || io_work<=0 {return 1;}
    let n=1;
    while n<=8 {
        let mask=0;
        while mask<(1<<n) {
            let begin=0;
            while begin<n {
                let observed=begin;
                while observed<n {
                    if (mask>>observed)&1 {
                        let retained=0;
                        while retained<n {
                            let marked=0;
                            while marked<2 {
                                let result=check_queue_case(n,mask,begin,observed,0,marked,retained);
                                if result {return result;}
                                result=check_queue_case(n,mask,begin,observed,n-1,marked,retained);
                                if result {return result;}
                                marked=marked+1;
                            }
                            retained=retained+1;
                        }
                    }
                    observed=observed+1;
                }
                begin=begin+1;
            }
            mask=mask+1;
        }
        n=n+1;
    }
    return 0;
}
