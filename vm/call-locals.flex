// Copy the arguments into the new frame and zero the rest of its locals.
// The caller must supply separate spans. This contract checks termination,
// access safety and effect bounds. Exact contents need a separate theorem.
requires count>=0 && count<=slots && slots<=4096;
requires readable_bytes(arguments,count*8);
requires writable_bytes(destination,slots*8);
requires disjoint_bytes(arguments,count*8,destination,slots*8);
reads bytes(arguments,count*8);
modifies bytes(destination,slots*8);
ensures result==slots;
fn vm_copy_call_locals(arguments,destination,count,slots) {
    let i=0;
    invariant i>=0 && i<=slots;
    invariant readable_bytes(arguments,count*8);
    invariant writable_bytes(destination,slots*8);
    decreases slots-i;
    while i<slots {
        let value=0;
        if i<count {
            proof {
                vm_call_local_offset(i,count);
                vm_call_local_readable(arguments,count*8,i*8);
            }
            value=load64(arguments+i*8);
        }
        proof {
            vm_call_local_offset(i,slots);
            vm_call_local_writable(destination,slots*8,i*8);
        }
        store64(destination+i*8,value);
        i=i+1;
    }
    return i;
}

requires length>=8 && length<=32768;
requires offset>=0 && offset<=length-8;
requires readable_bytes(base,length);
ensures readable_bytes(base+offset,8);
lemma fn vm_call_local_readable(base,length,offset) {}

requires length>=8 && length<=32768;
requires offset>=0 && offset<=length-8;
requires writable_bytes(base,length);
ensures writable_bytes(base+offset,8);
lemma fn vm_call_local_writable(base,length,offset) {}

requires length>=0 && length<=4096;
requires index>=0 && index<length;
ensures index*8>=0 && index*8<=length*8-8;
ensures index+1>=0 && index+1<=length;
lemma fn vm_call_local_offset(index,length) {
    assert index <= 4095;
    assert index+1 <= length;
    assert index*8+8 == (index+1)*8;
    assert (index+1)*8 <= length*8;
}
