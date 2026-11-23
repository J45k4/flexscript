// Proof profile for the guarded production relocation loop. The proof gate
// inserts that loop and uses the same checked patch32 as selected relocation.
requires vm_mode==0;
requires output_size>=0 && output_size<=67108864;
requires writable_bytes(output,output_size);
requires output>0 && output<=0x7fffffffffffffff-output_size;
requires vm_jit_error_count<0 || vm_jit_error_count>32768 || readable_bytes(vm_jit_errors,vm_jit_error_count*16);
modifies bytes(output,output_size);
ensures result==0 || (vm_jit_error_count>=0 && vm_jit_error_count<=32768);
ensures result==0 || result==1;
PRODUCTION_ERROR_LOOP

requires index>=0 && index<count && count<=32768;
requires readable_bytes(base,count*16);
ensures readable_bytes(base+index*16,16);
ensures index+1<=count;
ensures count-(index+1)>=0 && count-(index+1)<count-index;
lemma fn jit_error_row_step(base,index,count) {
    assert index<=32767;
    assert index+1<=count;
    assert index*16>=0 && index*16<=count*16-16;
    assert count-(index+1)+1==count-index;
}

requires offset>=2 && offset<=size-4 && size<=67108864;
requires base>0 && base<=0x7fffffffffffffff-size;
requires writable_bytes(base,size);
ensures offset+4>=0 && offset+4<=size;
ensures writable_bytes(base+offset,4);
lemma fn jit_error_patch_span(base,size,offset) {
    assert offset<=67108860;
    assert offset>=0 && offset<=size-4;
    assert offset+4>=0 && offset+4<=size;
    assert writable_bytes(base+offset,4);
}
