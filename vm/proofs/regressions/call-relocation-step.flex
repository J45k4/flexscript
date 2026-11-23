// Appended to both the checked and production projections of call-record relocation.
fn original_record_byte(byte_index) {return (byte_index*113+19)&255;}
fn expected_record_byte(idx,byte_in_record) {
    if byte_in_record>=16 && byte_in_record<24 {return ((idx*16+8)>>((byte_in_record-16)*8))&255;}
    return original_record_byte(16+idx*32+byte_in_record);
}
fn run_call_case(count,index,used,live) {
    call_count=count;
    output_size=487;
    let i=0;
    while i<288 {store8(calls-16+i,original_record_byte(i));i=i+1;}
    i=0;
    while i<8 {
        store64(calls+i*32+16,i*16+8);
        store64(io_map+i*8,i*32+48);
        store8(io_flags+i,2);
        i=i+1;
    }
    store8(io_flags+index,2+live);
    let mapped=index*32+48;
    if io_call_relocation_step(index,used,index*16,mapped,(index+used)&31,live,count,calls-16)!=used+live {return 1;}
    if output_size!=487 {return 2;}
    i=0;
    while i<288 {
        let expected=original_record_byte(i);
        if i>=16 && i<272 {
            let idx=(i-16)/32;
            let byte_in_record=(i-16)&31;
            expected=expected_record_byte(idx,byte_in_record);
            if live && (idx==index || idx==used) {
                expected=expected_record_byte(index,byte_in_record);
                if byte_in_record>=16 && byte_in_record<24 {
                    expected=((mapped+8)>>((byte_in_record-16)*8))&255;
                }
            }
        }
        if load8(calls-16+i)!=expected {return 3;}
        i=i+1;
    }
    i=0;
    while i<8 {
        let expected=2;
        if i==index {expected=2+live;}
        if load8(io_flags+i)!=expected || load64(io_map+i*8)!=i*32+48 {return 4;}
        i=i+1;
    }
    return 0;
}
fn main() {
    calls=alloc(288)+16;
    io_flags=alloc(8);
    io_map=alloc(64);
    if calls<=16 || io_flags<=0 || io_map<=0 {return 5;}
    let count=1;
    while count<=8 {
        let index=0;
        while index<count {
            let used=0;
            while used<=index {
                let result=run_call_case(count,index,used,0);
                if result {return result;}
                result=run_call_case(count,index,used,1);
                if result {return result;}
                used=used+1;
            }
            index=index+1;
        }
        count=count+1;
    }
    return 0;
}
