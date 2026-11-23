// A call at a valid depth writes one record in the frame allocation.
requires depth>=0 && depth<1024;
requires writable_bytes(frames,40960);
ensures writable_bytes(frames+depth*40,40);
lemma fn call_frame_record_writable(frames,depth) {
    assert depth*40>=0 && depth*40<=40920;
}

requires depth>=1 && depth<1024;
requires writable_bytes(frames,40960);
ensures readable_bytes(frames+(depth-1)*40+24,8);
lemma fn call_frame_floor_readable(frames,depth) {
    assert depth-1>=0 && depth-1<=1022;
    assert (depth-1)*40+24>=0 && (depth-1)*40+24<=40952;
}
