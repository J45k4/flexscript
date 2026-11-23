requires first<=middle && middle<=last;
ensures first<=last;
lemma fn vm_frame_offset_order(first,middle,last) {}

requires low>=0 && low<=high && high<=1023;
ensures low*40<=high*40;
decreases high-low;
lemma fn vm_frame_stride_order(low,high) {
    if low==high {return 0;}
    assert high-1>=low && high-1>=0 && high-1<=1022;
    proof {vm_frame_stride_order(low,high-1);}
    assert (high-1)*40>=0 && (high-1)*40<=40880;
    assert (high-1)*40+40==high*40;
    assert (high-1)*40<=high*40;
    proof {vm_frame_offset_order(low*40,(high-1)*40,high*40);}
}

// Any complete word in an older record is outside the new record.
requires prior>=0 && prior<depth && depth<1024;
requires field>=0 && field<=32;
requires frames>=1 && frames<=0x7fffffffffff6000;
ensures disjoint_bytes(frames+(prior*40+field),8,frames+depth*40,40);
lemma fn vm_older_record_separation(frames,prior,depth,field) {
    assert prior+1<=depth;
    assert prior*40+40==(prior+1)*40;
    proof {vm_frame_stride_order(prior+1,depth);}
    assert prior*40+field+8<=depth*40;
    let older=frames+(prior*40+field);
    let newer=frames+depth*40;
    // Comparing with an empty span checks validity independently of overlap.
    assert disjoint_bytes(older,8,0,0);
    assert disjoint_bytes(newer,40,0,0);
    assert newer-older>=8;
}

requires writable_bytes(frames,40960);
ensures frames>=1 && frames<=0x7fffffffffff6000;
lemma fn vm_frame_address_bounds(frames) {}

requires offset>=0 && offset<=40952;
requires writable_bytes(frames,40960);
ensures readable_bytes(frames+offset,8);
lemma fn vm_older_word_readable(frames,offset) {}

requires prior>=0 && prior<=1023;
requires field>=0 && field<=32;
ensures prior*40+field>=0 && prior*40+field<=40952;
lemma fn vm_older_word_offset(prior,field) {
    assert prior*40>=0 && prior*40<=40920;
    assert prior*40+field>=0 && prior*40+field<=40952;
}

requires prior>=0 && prior<=1023;
requires field>=0 && field<=32;
requires slots>=0 && slots<=4096;
requires local_base>=0 && local_base<=8388608 && local_base+slots*8<=8388608;
requires disjoint_bytes(frames,40960,locals,8388608);
ensures disjoint_bytes(frames+(prior*40+field),8,locals+local_base,slots*8);
lemma fn vm_older_word_separate_from_copy(frames,locals,prior,field,local_base,slots) {
    assert prior*40>=0 && prior*40<=40920;
    assert prior*40+field>=0 && prior*40+field<=40952;
    assert slots*8>=0 && slots*8<=32768;
    assert local_base<=8388608-slots*8;
}

// A complete word in the live prefix can start at any byte offset, including
// an offset that straddles two earlier records.
requires offset>=0 && offset<=40952 && offset+8<=depth*40;
requires depth>=0 && depth<1024;
requires frames>=1 && frames<=0x7fffffffffff6000;
ensures disjoint_bytes(frames+offset,8,frames+depth*40,40);
lemma fn vm_older_offset_separation(frames,offset,depth) {
    assert depth*40>=0 && depth*40<=40920;
    let older=frames+offset;
    let newer=frames+depth*40;
    assert disjoint_bytes(older,8,0,0);
    assert disjoint_bytes(newer,40,0,0);
    assert newer-older>=8;
}

requires offset>=0 && offset<=40952;
requires slots>=0 && slots<=4096;
requires local_base>=0 && local_base<=8388608 && local_base+slots*8<=8388608;
requires disjoint_bytes(frames,40960,locals,8388608);
ensures disjoint_bytes(frames+offset,8,locals+local_base,slots*8);
lemma fn vm_older_offset_separate_from_copy(frames,locals,offset,local_base,slots) {
    assert slots*8>=0 && slots*8<=32768;
    assert local_base<=8388608-slots*8;
}

// An observed frame word inherits separation from its backing region.
requires frame_size>=8 && frame_size<=40960;
requires offset>=0 && offset<=frame_size-8;
requires disjoint_bytes(frames,frame_size,pointer,length);
ensures disjoint_bytes(frames+offset,8,pointer,length);
lemma fn vm_frame_word_separate_from_region(frames,frame_size,offset,pointer,length) {}
