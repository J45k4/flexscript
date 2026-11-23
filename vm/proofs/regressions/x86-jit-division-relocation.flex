fn verify_record(row,at,delta) {
    let slot=vm_jit_errors+row*16;
    let end=at+delta+4;
    store64(slot,at);store64(slot+8,2);
    store8(output+at-2,15);store8(output+at-1,132);
    store8(output+at+4,177);
    if vm_jit_patch_division_record(row,row,at,end+1,end+2,end,end+3,end+4)!=row+1 {return 2;}
    if load64(slot)!=at || load64(slot+8)!=2 {return 3;}
    if load8(output+at-2)!=15 || load8(output+at-1)!=132 || load8(output+at+4)!=177 {return 4;}
    let offset=load8(output+at)|(load8(output+at+1)<<8)|(load8(output+at+2)<<16)|(load8(output+at+3)<<24);
    if at+4+offset!=end {return 5;}
    return 0;
}
fn main() {
    output=alloc(256);vm_jit_errors=alloc(128);
    if output<=0 || vm_jit_errors<=0 {return 1;}
    vm_mode=0;
    let row=0;
    while row<8 {
        let at=2;
        while at<=248 {
            let status=verify_record(row,at,0);
            if status {return status;}
            let shift=0;
            while shift<26 {
                let delta=(1<<shift)-1;
                status=verify_record(row,at,delta);
                if status {return status;}
                status=verify_record(row,at,delta+1);
                if status {return status;}
                shift=shift+1;
            }
            at=at+1;
        }
        row=row+1;
    }
    return 0;
}
