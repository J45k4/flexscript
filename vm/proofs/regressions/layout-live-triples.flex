import "../../../compiler/ir-layout.flex";

fn triple_fixture(count,first,mode) {
    let i=0;
    let prefix=0;
    let total=0;
    while i<count {
        let live=mode==1 || (mode==2 && (i%3)!=1);
        if i>=first && i<=first+2 {live=1;}
        store8(io_flags+i,180|live);
        if i<first {prefix=prefix+live;}
        total=total+live;
        i=i+1;
    }
    let size=io_build_layout(count);
    if size!=total*16 || load64(io_map+count*8)!=size {return 1;}
    let at=io_compacted_offset(first*16);
    if at!=prefix*16 || at>size-48 {return 2;}
    if io_compacted_offset((first+1)*16)!=at+16 {return 3;}
    if io_compacted_offset((first+2)*16)!=at+32 {return 4;}
    return 0;
}
fn main() {
    io_flags=alloc(257);
    io_map=alloc((257+1)*8);
    if io_flags<0 || io_map<0 {return 5;}
    let mode=0;
    while mode<3 {
        let count=3;
        while count<=32 {
            let first=0;
            while first<=count-3 {
                let status=triple_fixture(count,first,mode);
                if status {return status;}
                first=first+1;
            }
            count=count+1;
        }
        let status=triple_fixture(257,254,mode);
        if status {return status;}
        mode=mode+1;
    }
    return 0;
}
