// Native bounds cases for the production and annotated call-record loop.
fn check_bad_call_record(value) {
    call_count=1;
    store64(calls+16,value);
    if io_relocate_guarded_calls(2)!=-1 {return 1;}
    if load64(calls+16)!=value || call_count!=1 || output_size!=37 {return 2;}
    return 0;
}
fn main() {
    calls=alloc(65536*32);
    io_flags=alloc(2);
    io_map=alloc(24);
    if calls<=0 || io_flags<=0 || io_map<=0 {return 3;}
    output_size=37;
    call_count=65536;
    let i=0;
    while i<call_count {
        store64(calls+i*32+16,24);
        store64(calls+i*32+24,i);
        i=i+1;
    }
    store8(io_flags+1,0);
    store64(io_map+8,0);
    if io_relocate_guarded_calls(2)!=0 {return 4;}
    i=0;
    while i<call_count {
        if load64(calls+i*32+16)!=24 || load64(calls+i*32+24)!=i {return 5;}
        i=i+1;
    }
    store8(io_flags+1,1);
    if io_relocate_guarded_calls(2)!=65536 {return 6;}
    if output_size!=37 || call_count!=65536 {return 7;}
    i=0;
    while i<call_count {
        if load64(calls+i*32+16)!=8 || load64(calls+i*32+24)!=i {return 8;}
        i=i+1;
    }
    call_count=0;
    if io_relocate_guarded_calls(0)!=0 {return 9;}
    if check_bad_call_record(0) || check_bad_call_record(9) || check_bad_call_record(40) ||
        check_bad_call_record(0x8000000000000000) || check_bad_call_record(0x7fffffffffffffff) {return 10;}
    let count=16777216;
    io_flags=alloc(count);
    io_map=alloc((count+1)*8);
    if io_flags<=0 || io_map<=0 {return 11;}
    store8(io_flags+count-1,1);
    store64(io_map+(count-1)*8,0);
    store64(calls+16,count*16-8);
    if io_relocate_guarded_calls(count)!=1 || load64(calls+16)!=8 {return 12;}
    return 0;
}
