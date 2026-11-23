fn main() {
    io_flags=alloc(8);
    if io_flags<=0 {return 1;}
    let n=1;
    while n<=8 {
        let mask=0;
        while mask<(1<<n) {
            let i=0;
            while i<n {
                store8(io_flags+i,((mask>>i)&1)|0x84);
                i=i+1;
            }
            let begin=0;
            while begin<n {
                let expected=begin;
                while expected<n && !((mask>>expected)&1) {expected=expected+1;}
                let observed=begin;
                while observed<n {
                    let result=io_next_observed(begin*16,n*16,observed*16);
                    if result!=expected*16 {return 2;}
                    if observed*16<result && ((mask>>observed)&1) {return 3;}
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
