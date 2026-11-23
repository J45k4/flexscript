fn check_seed(count,entry,flag) {
    let row=0;
    while row<=count {
        store8(io_flags+row,(77+row)&255);
        store64(io_work+row*8,1700+row);
        row=row+1;
    }
    store8(io_flags+entry,flag);
    let start=entry*16;
    let operand=0x8000100000000000+flag+entry;
    store64(io_code+start,18);
    store64(io_code+start+8,operand);
    if io_reach_seed(start,count*16)!=1 || load64(io_work)!=start {return 2;}
    if load64(io_code+start)!=18 || load64(io_code+start+8)!=operand {return 3;}
    row=0;
    while row<=count {
        let expected=(77+row)&255;
        if row==entry {expected=flag|4;}
        if load8(io_flags+row)!=expected {return 4;}
        if row && load64(io_work+row*8)!=1700+row {return 5;}
        row=row+1;
    }
    return 0;
}

fn check_seeds() {
    io_flags=alloc(21);io_work=alloc(168);io_code=alloc(320);
    if io_flags<=0 || io_work<=0 || io_code<=0 {return 1;}
    let count=1;
    while count<=20 {
        let entry=0;
        while entry<count {
            let flag=0;
            while flag<256 {
                if (flag&5)==1 {
                    let status=check_seed(count,entry,flag);
                    if status {return status;}
                }
                flag=flag+1;
            }
            entry=entry+1;
        }
        count=count+1;
    }
    return 0;
}

fn check_flag_initialization() {
    let arena=alloc(132);
    if arena<=0 {return 1;}
    let slots=1;
    while slots<=128 {
        let bias=0;
        while bias<4 {
            io_flags=arena+bias;
            let i=0;
            while i<132 {store8(arena+i,0xa5);i=i+1;}
            let observed=(slots/4)*(bias+1)%slots;
            io_initialize_observed_flag(slots*16,observed*16);
            i=0;
            while i<132 {
                let expected=0xa5;
                if i>=bias && i<bias+slots {expected=1;}
                if load8(arena+i)!=expected {return 2;}
                i=i+1;
            }
            bias=bias+1;
        }
        slots=slots+1;
    }
    return 0;
}

fn main() {
    let status=check_flag_initialization();
    if status {return status;}
    status=check_seeds();
    if status {return status+8;}
    return 0;
}
