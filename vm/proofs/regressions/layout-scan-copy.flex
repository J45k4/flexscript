import "../../../compiler/ir-layout.flex";

fn scan_copy_fixture(count,first,mode,record) {
    let i=0;
    let prefix=0;
    let total=0;
    while i<count {
        let live=mode==1 || (mode==2 && (i%3)!=1);
        if i>=first && i<=first+2 {live=1;}
        store8(io_flags+i,180|live);
        store64(output+i*16,-47);
        store64(output+i*16+8,-81);
        if live {
            total=total+1;
            if i<first {prefix=prefix+1;}
        }
        i=i+1;
    }
    let header_pc=first*16;
    let push_pc=header_pc+16;
    let return_pc=push_pc+16;
    let arity=first%9;
    let slots=arity+count%5;
    let push_arg=0x173295a682413b7f^(first*343);
    let return_arg=0xdbac97464132451b^(count*739);
    store64(io_code+header_pc,18);
    store64(io_code+header_pc+8,slots);
    store64(io_code+push_pc,2);
    store64(io_code+push_pc+8,push_arg);
    store64(io_code+return_pc,9);
    store64(io_code+return_pc+8,return_arg);

    store64(record,1297);
    store64(record+8,31);
    store64(record+16,header_pc);
    store64(record+24,arity);
    let size=io_build_layout(count);
    let at=io_compacted_offset(header_pc);
    io_write_compacted_instruction(header_pc,io_compacted_offset(header_pc));
    io_write_compacted_instruction(push_pc,io_compacted_offset(push_pc));
    io_write_compacted_instruction(return_pc,io_compacted_offset(return_pc));
    io_relocate_function(record,load64(record+16));
    if size!=total*16 || load64(io_map+count*8)!=size || at!=prefix*16 || at+48>size {return 1;}
    if load64(output+at+16)!=2 || load64(output+at+24)!=push_arg {return 2;}
    if load64(output+at+32)!=9 || load64(output+at+40)!=return_arg {return 3;}
    if load64(io_code+push_pc)!=2 || load64(io_code+push_pc+8)!=push_arg {return 4;}
    if load64(io_code+return_pc)!=9 || load64(io_code+return_pc+8)!=return_arg {return 5;}
    if load64(output+at)!=18 || load64(output+at+8)!=slots {return 8;}
    if load64(record+16)!=at || load64(record+24)!=arity {return 9;}
    if load64(record)!=1297 || load64(record+8)!=31 {return 10;}
    if load64(io_code+header_pc)!=18 || load64(io_code+header_pc+8)!=slots {return 11;}
    i=0;
    while i<count {
        let p=i*16;
        if p!=at && p!=at+16 && p!=at+32 && (load64(output+p)!= -47 || load64(output+p+8)!= -81) {return 6;}
        i=i+1;
    }
    return 0;
}

fn main() {
    io_flags=alloc(257);
    io_map=alloc((257+1)*8);
    io_code=alloc(257*16);
    output=alloc(257*16);
    let record=alloc(32);
    if io_flags<0 || io_map<0 || io_code<0 || output<0 || record<0 {return 7;}
    let mode=0;
    while mode<3 {
        let count=3;
        while count<=32 {
            let first=0;
            while first<=count-3 {
                let status=scan_copy_fixture(count,first,mode,record);
                if status {return status;}
                first=first+1;
            }
            count=count+1;
        }
        let status=scan_copy_fixture(257,254,mode,record);
        if status {return status;}
        mode=mode+1;
    }
    return 0;
}
