import "../call-frame.flex";
import "../../compiler/ir-layout.flex";

requires count>=1 && count<=16777216;
requires index>=0 && index<=count;
requires observe>=0 && observe<index;
requires writable_bytes(map,(count+1)*8);
ensures disjoint_bytes(map+index*8,8,map+observe*8,8);
lemma fn io_layout_previous_word(map,index,observe,count) {
    assert index*8<=count*8;
    assert (count+1)*8-8==count*8;
    assert writable_bytes(map+index*8,8);
    io_layout_index(observe,count);
    assert writable_bytes(map+observe*8,8);
    assert index-observe>=1;
    assert (map+index*8)-(map+observe*8)==(index-observe)*8;
    assert (index-observe)*8>=8;
}

requires count>=1 && count<=16777216;
requires observe>=0 && observe<=count-1;
requires disjoint_bytes(map,(count+1)*8,flags,count);
ensures disjoint_bytes(map,(count+1)*8,flags+observe,1);
lemma fn io_layout_observed_flag(map,flags,count,observe) {}

requires count>=1 && count<=16777216;
requires i>=0 && i<count;
requires bytes>=0 && bytes<=i*16 && (bytes&15)==0;
requires live==0 || live==1;
ensures bytes+live*16>=0 && bytes+live*16>=bytes;
ensures bytes+live*16<=(i+1)*16;
ensures ((bytes+live*16)&15)==0;
lemma fn io_layout_advance(bytes,i,count,live) {}

requires count>=1 && count<=16777216;
requires i>=0 && i<=count && observe>=0 && observe<=count-1;
requires i*8>=0 && i*8<=(count+1)*8-8;
requires disjoint_bytes(map,(count+1)*8,flags,count);
ensures disjoint_bytes(map+i*8,8,flags+observe,1);
lemma fn io_layout_flag_separation(map,flags,count,i,observe) {}

requires before>=0 && before<=268435440;
requires after>=before && after<=268435456;
requires at<=before-16;
ensures at<=after-16;
lemma fn io_layout_keep_limit(at,before,after) {}

requires index==observe;
ensures flags+index==flags+observe;
ensures map+index*8==map+observe*8;
lemma fn io_layout_observer_addresses(map,flags,index,observe) {}


requires first==second;
requires readable_bytes(first,1);
ensures load8(first)==load8(second);
lemma fn io_layout_same_flag(first,second) {}

requires first==second;
requires readable_bytes(first,8);
ensures load64(first)==load64(second);
lemma fn io_layout_same_word(first,second) {}

requires i>=0 && i<16777216;
requires observe>=0 && observe<16777216;
ensures (i+1<=observe)==(i<observe);
lemma fn io_layout_observed_crossing(i,observe) {}

requires i>observe;
requires (i<=observe) | (recorded<=bytes-16);
ensures recorded<=bytes-16;
lemma fn io_layout_observed_within(i,observe,recorded,bytes) {}

requires actual==recorded;
requires recorded<=bytes-16;
ensures actual<=bytes-16;
lemma fn io_layout_observed_bound(actual,recorded,bytes) {}

// For any selected live slot, the completed production scan leaves its
// aligned offset inside the compacted program. The VM proof gate inserts
// the production body with only proof annotations added.
requires count>=1 && count<=16777216;
requires observe>=0 && observe<count;
requires writable_bytes(io_map,(count+1)*8);
requires readable_bytes(io_flags,count);
requires disjoint_bytes(io_map,(count+1)*8,io_flags,count);
requires readable_bytes(io_map+observe*8,8);
requires readable_bytes(io_flags+observe,1);
requires (load8(io_flags+observe)&1)==1;
modifies bytes(io_map,(count+1)*8);
ensures result>=0 && result<=count*16 && (result&15)==0;
ensures load64(io_map+count*8)==result;
ensures load64(io_map+observe*8)>=0;
ensures load64(io_map+observe*8)<=result-16;
ensures (load64(io_map+observe*8)&15)==0;
fn io_build_layout_observed(count,observe) {
    // Production layout body.

}

requires observe>=0 && observe<16777216;
ensures (observe*16)/2==observe*8;
lemma fn io_layout_pc_slot(observe) {}

requires size>=0 && size<=268435456;
requires at>=0 && at<=size-16;
ensures size>=16;
lemma fn io_layout_nonempty_size(at,size) {}

requires count>=1 && count<=16777216;
requires observe>=0 && observe<count;
requires writable_bytes(io_map,(count+1)*8);
requires readable_bytes(io_flags,count);
requires disjoint_bytes(io_map,(count+1)*8,io_flags,count);
requires readable_bytes(io_flags+observe,1);
requires (load8(io_flags+observe)&1)==1;
modifies bytes(io_map,(count+1)*8);
ensures result==0;
fn optimizer_layout_observed_offset_passes_guard(count,observe) {
    proof {
        io_layout_index(observe,count);
        io_layout_region(io_map,io_flags,observe,count);
        assert readable_bytes(io_map+observe*8,8);
    }
    let size=io_build_layout_observed(count,observe);
    proof {io_layout_pc_slot(observe);}
    let at=io_compacted_offset(observe*16);
    proof {
        io_layout_same_word(io_map+(observe*16)/2,io_map+observe*8);
        assert at==load64(io_map+observe*8);
        io_layout_nonempty_size(at,size);
    }
    return vm_instruction_outside(at,size);
}
