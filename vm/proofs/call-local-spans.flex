// The operand cursor points past the arguments. The local base points at
// the first slot of the new frame. Derive permissions from the full buffers.
requires count>=0 && count<=4096;
requires sp>=0 && sp<=524288 && count*8<=sp;
requires writable_bytes(stack,524288);
ensures readable_bytes(stack+(sp-count*8),count*8);
lemma fn vm_call_argument_span(stack,sp,count) {
    let length=count*8;
    let start=sp-length;
    assert length>=0 && length<=32768;
    assert start>=0 && start<=524288-length;
}

requires slots>=0 && slots<=4096;
requires local_base>=0 && local_base<=8388608 && local_base+slots*8<=8388608;
requires writable_bytes(locals,8388608);
ensures writable_bytes(locals+local_base,slots*8);
lemma fn vm_call_destination_span(locals,local_base,slots) {
    assert slots*8>=0 && slots*8<=32768;
    assert local_base<=8388608-slots*8;
}

requires count>=0 && count<=slots && slots<=4096;
requires sp>=0 && sp<=524288 && count*8<=sp;
requires local_base>=0 && local_base<=8388608 && local_base+slots*8<=8388608;
requires disjoint_bytes(stack,524288,locals,8388608);
ensures disjoint_bytes(stack+(sp-count*8),count*8,locals+local_base,slots*8);
lemma fn vm_call_spans_separated(stack,locals,sp,local_base,count,slots) {
    assert count*8>=0 && count*8<=32768;
    assert slots*8>=0 && slots*8<=32768;
    proof {vm_call_argument_bounds(sp,count*8);}
    assert local_base<=8388608-slots*8;
}

requires sp>=0 && sp<=524288;
requires length>=0 && length<=32768 && length<=sp;
ensures sp-length>=0;
ensures sp-length<=524288-length;
lemma fn vm_call_argument_bounds(sp,length) {assert sp>=length;}

requires depth>=0 && depth<1024;
requires slots>=0 && slots<=4096;
requires local_base>=0 && local_base<=8388608 && local_base+slots*8<=8388608;
requires disjoint_bytes(frames,40960,locals,8388608);
ensures disjoint_bytes(frames+depth*40,40,locals+local_base,slots*8);
lemma fn vm_saved_record_separate_from_copy(frames,locals,depth,local_base,slots) {
    assert depth*40>=0 && depth*40<=40920;
    assert slots*8>=0 && slots*8<=32768;
    assert local_base<=8388608-slots*8;
}

requires depth>=1 && depth<1024;
requires slots>=0 && slots<=4096;
requires local_base>=0 && local_base<=8388608 && local_base+slots*8<=8388608;
requires disjoint_bytes(frames,40960,locals,8388608);
ensures disjoint_bytes(frames+(depth-1)*40+24,8,locals+local_base,slots*8);
lemma fn vm_caller_floor_separate_from_copy(frames,locals,depth,local_base,slots) {
    assert depth-1>=0 && depth-1<=1022;
    assert (depth-1)*40+24>=0 && (depth-1)*40+24<=40952;
    assert slots*8>=0 && slots*8<=32768;
    assert local_base<=8388608-slots*8;
}
