fn check_ordinary_step(n,mask,pc,opcode,target,witness,initial,marked) {
    let read=initial-1;
    let chosen=target;
    if opcode!=10 {chosen=pc+1;}
    if opcode!=9 {
        while chosen<n && !((mask>>chosen)&1) {chosen=chosen+1;}
        if chosen>witness {return 1;}
    }
    let i=0;
    while i<n {
        let flag=0x82|((mask>>i)&1);
        if opcode!=9 && marked && i==chosen {flag=flag|4;}
        store8(io_flags+i,flag);
        let value=700+i;
        if i==read {value=pc*16;}
        store64(io_work+i*8,value);
        i=i+1;
    }
    store64(io_code+pc*16,opcode);
    store64(io_code+pc*16+8,target*16);
    let result=0;
    if opcode==9 {
        result=io_reach_return_step(read,initial,n*16,pc*16);
    }else {
        result=io_reach_single_successor_step(read,initial,n*16,pc*16,opcode,target*16,witness*16);
    }
    let appended=opcode!=9 && !marked;
    if result!=initial+appended {return 2;}
    i=0;
    while i<n {
        let flag=0x82|((mask>>i)&1);
        if opcode!=9 && i==chosen {flag=flag|4;}
        if load8(io_flags+i)!=flag {return 3;}
        let expected=700+i;
        if i==read {expected=pc*16;}
        if i==initial && appended {expected=chosen*16;}
        if load64(io_work+i*8)!=expected {return 4;}
        i=i+1;
    }
    return 0;
}

fn main() {
    io_flags=alloc(8);
    io_work=alloc(64);
    io_code=alloc(128);
    if io_flags<=0 || io_work<=0 || io_code<=0 {return 1;}
    let n=1;
    while n<=8 {
        let mask=0;
        while mask<(1<<n) {
            let witness=n-1;
            while witness>=0 && !((mask>>witness)&1) {witness=witness-1;}
            let pc=0;
            while pc<n {
                let bad=check_ordinary_step(n,mask,pc,9,0,0,n,0);
                if bad {return bad;}
                if n>1 {
                    let marked=0;
                    while marked<2 {
                        if pc<witness {
                            bad=check_ordinary_step(n,mask,pc,1,0,witness,1,marked);
                            if bad {return bad;}
                            bad=check_ordinary_step(n,mask,pc,18,0,witness,n-1,marked);
                            if bad {return bad;}
                        }
                        let target=0;
                        while target<=witness {
                            bad=check_ordinary_step(n,mask,pc,10,target,witness,1,marked);
                            if bad {return bad;}
                            bad=check_ordinary_step(n,mask,pc,10,target,witness,n-1,marked);
                            if bad {return bad;}
                            target=target+1;
                        }
                        marked=marked+1;
                    }
                }
                pc=pc+1;
            }
            mask=mask+1;
        }
        n=n+1;
    }
    return 0;
}
