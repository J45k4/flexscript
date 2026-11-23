// Carry the production record offsets through interval and header admission.
requires capacity>=2048 && capacity<=18432;
requires index>=0 && index<function_count && function_count<=capacity;
requires writable_bytes(functions,capacity*32);
requires output_size>=0 && output_size<=268435456;
requires readable_bytes(output,output_size);
ensures result==0 || (result>=1 && result<=8192);
ensures result==0 || readable_bytes(output+load64(functions+index*32+16),result*16);
ensures result==0 || readable_bytes(output+load64(functions+index*32+16),16);
ensures result==0 || load64(output+load64(functions+index*32+16))==18;
ensures result==0 || (load64(output+load64(functions+index*32+16)+8)>=0 && load64(output+load64(functions+index*32+16)+8)<=4096);
ensures result==0 || index+1>=function_count || load64(functions+(index+1)*32+16)==load64(functions+index*32+16)+result*16;
ensures result==0 || index+1<function_count || output_size==load64(functions+index*32+16)+result*16;
fn jit_leaf_metadata_from_records(index,capacity) {
PRODUCTION_LEAF_RECORD_READS
    let count=jit_check_leaf_interval(start,end,bytecode_size);
    if count==0 {return 0;}
    proof {
        assert start>=0 && end<=bytecode_size;
        assert count>=1 && count<=8192;
        jit_leaf_full_span(bytecode,bytecode_size,start,count*16,end);
    }
    if jit_check_leaf_header(bytecode,start)<0 {return 0;}
    return count;
}

requires readable_bytes(record,32);
ensures readable_bytes(record+16,8);
lemma fn jit_leaf_record_pc_grant(record) {}

requires start>=0 && start<end && end<=size && size<=268435456;
requires length>=16 && length<=131072;
requires end==start+length;
requires readable_bytes(bytecode,size);
ensures readable_bytes(bytecode+start,length);
ensures readable_bytes(bytecode+start,16);
ensures start>=0 && start<=268435440;
lemma fn jit_leaf_full_span(bytecode,size,start,length,end) {
    jit_leaf_span_bounds(start,length,end,size);
    assert start<=size-length;
    assert start<=size-16;
    assert size-16<=268435440;
}

PRODUCTION_FUNCTION_RECORD_GRANTS

requires index>=0 && index<count;
requires count<=capacity && capacity<=18432;
ensures index<capacity;
lemma fn jit_leaf_record_index(index,count,capacity) {}

requires start>=0 && start<end && end<=size && size<=268435456;
requires length>=16 && length<=131072;
requires end==start+length;
ensures start<=size-length;
ensures start<=size-16;
lemma fn jit_leaf_span_bounds(start,length,end,size) {
    assert start<=268435456;
    assert end>=length;
    assert size>=length;
    assert size-length>=0 && size-length<=268435456;
    let available=size-length;
    assert length+available==size;
    assert length+start==end;
    if available<start {
        jit_leaf_add_keeps_order(available,start,length);
        jit_leaf_transfer_order(size,end,length+available,length+start);
    }
    assert start<=available;
    assert size-length<=size-16;
}

requires first>=0 && first<later && later<=268435456;
requires length>=16 && length<=131072;
ensures length+first<length+later;
lemma fn jit_leaf_add_keeps_order(first,later,length) {
    let lower=length+first;
    let upper=length+later;
    assert lower>=0 && lower<=268566528;
    assert upper>=0 && upper<=268566528;
    assert upper-lower==later-first;
    assert later-first>=1;
}

requires lower==left && upper==right;
requires left<right;
ensures lower<upper;
lemma fn jit_leaf_transfer_order(lower,upper,left,right) {}
