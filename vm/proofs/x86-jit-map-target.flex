// The branch admission and lookup come from the production JIT.
// The emitter output offsets are supplied by the immutable trace.
requires start>=0 && start<=268435440;
requires end>start && end<=268435456;
requires (end-start)%16==0 && (end-start)/16<=8192;
requires start%16==0;
requires op==10 || op==11 || op==12;
ensures result== -1 || result>=1;
ensures result== -1 || result<(end-start)/16;
ensures result== -1 || start+result*16==arg;
ensures result== -1 || result==(arg-start)/16;
ensures arg<start+16 || arg>=end || arg%16 || result!= -1;
fn jit_validate_branch_target(start,end,op,arg) {
PRODUCTION_TARGET_GUARD
    proof {
        jit_branch_offsets_positive(start,arg,end);
        jit_branch_offsets_aligned(start,arg);
        jit_branch_map_slot_from_offsets(start,arg,arg-start,end-start);
    }
PRODUCTION_TARGET_INDEX
}

requires start>=0 && start<=268435440;
requires arg>=start+16 && arg<end && end<=268435456;
ensures arg-start>=16 && arg-start<end-start;
lemma fn jit_branch_offsets_positive(start,arg,end) {
    let distance=arg-start;
    assert arg>=start && start>=0;
    assert distance>=0;
    assert start+distance==arg;
    if distance<16 {
        assert distance<=15;
        assert start+distance<=start+15;
    }
    assert distance>=16;
    let extent=end-start;
    assert extent>0 && extent<=268435456;
    assert distance<=268435456;
    assert start+extent==end;
    proof {jit_compare_leaf_offsets(start,distance,extent,arg,end);}
}

requires start>=0 && arg>=start && arg<=268435456;
requires start%16==0 && arg%16==0;
ensures (arg-start)%16==0;
lemma fn jit_branch_offsets_aligned(start,arg) {
    assert (start&15)==0 && (arg&15)==0;
    assert arg-start>=0;
    assert ((arg-start)&15)==0;
}

requires start>=0 && start<=268435440 && arg>=start+16 && arg<=268435456;
requires distance==arg-start && distance>=16 && distance<extent;
requires extent<=268435456 && extent/16<=8192;
requires distance%16==0 && extent%16==0;
ensures distance/16>=1 && distance/16<extent/16;
ensures start+(distance/16)*16==arg;
lemma fn jit_branch_map_slot_from_offsets(start,arg,distance,extent) {
    assert start+distance==arg;
    assert (distance&15)==0;
    assert (extent&15)==0;
    assert ((distance>>4)<<4)==distance && ((extent>>4)<<4)==extent;
    assert distance/16==distance>>4;
    assert extent/16==extent>>4;
    assert distance/16<extent/16;
}

requires base>=0 && base<=268435440;
requires pos>=0 && pos<=268435456;
requires limit>=0 && limit<=268435456;
requires a==base+pos && b==base+limit && a<b;
ensures pos<limit;
lemma fn jit_compare_leaf_offsets(base,pos,limit,a,b) {
    if pos>=limit {
        assert base+pos>=base+limit;
    }
}
requires start>=0 && start<=67108848 && start%16==0;
requires map_count>=2 && map_count<=8192;
requires end==start+map_count*16 && end>start && end<=67108864;
requires (end-start)%16==0 && (end-start)/16<=8192;
requires observed>=1 && observed<map_count && arg==start+observed*16;
requires op==10 || op==11 || op==12;
requires size>=1 && size<=67108864;
requires writable_bytes(vm_jit_map,8193*8);
requires readable_bytes(offsets,8193*8);
requires disjoint_bytes(vm_jit_map,8193*8,offsets,8193*8);
requires readable_bytes(vm_jit_map+observed*8,8);
requires readable_bytes(offsets+observed*8,8);
requires disjoint_bytes(vm_jit_map,8193*8,offsets+observed*8,8);
modifies bytes(vm_jit_map,8193*8);
ensures result== -1 || result==old(load64(offsets+observed*8));
ensures result== -1 || (result>=0 && result<size);
fn jit_record_map_and_lookup(start,end,map_count,offsets,op,arg,observed,size) {
    proof {jit_record_map_extent(start,end,map_count);}
    let index=jit_validate_branch_target(start,end,op,arg);
    if index<1 || index>=map_count {return -1;}
    proof {
        assert index!= -1;
        assert start+index*16==arg;
        jit_map_index_range(index,observed,map_count);
        jit_map_index_unique(start,index,observed,arg);
        jit_record_map_alias(vm_jit_map,index,observed);
    }
    jit_record_map_prefix(start,end,map_count,offsets,observed);
    proof {jit_record_map_equal_word(vm_jit_map+index*8,vm_jit_map+observed*8);}
PRODUCTION_MAP_TARGET_READ
    return target;
}

requires start>=0 && start<=67108864;
requires count>=1 && count<=8192;
requires end==start+count*16 && end<=67108864;
ensures (end-start)%16==0 && (end-start)/16==count;
lemma fn jit_record_map_extent(start,end,count) {
    assert end-start==count*16;
    assert (count*16)%16==0;
    assert (count*16)/16==count;
}

requires actual>=1 && actual<=8191 && observed>=1 && observed<=8191;
requires start+actual*16==arg && start+observed*16==arg;
ensures actual==observed;
lemma fn jit_map_index_unique(start,actual,observed,arg) {
    assert actual*16==observed*16;
    assert (actual*16)/16==actual && (observed*16)/16==observed;
}

requires index>=1 && index<count && observed>=1 && observed<count;
requires count<=8192;
ensures index>=1 && index<=8191 && observed>=1 && observed<=8191;
lemma fn jit_map_index_range(index,observed,count) {}

requires start>=0 && start<=268435440 && start%16==0;
requires count>=2 && count<=8192;
requires end==start+count*16 && end<=268435456;
requires arg>=start+16 && arg<end && arg%16==0;
requires op==10 || op==11 || op==12;
ensures result>=1 && result<count;
ensures result==(arg-start)/16;
ensures start+result*16==arg;
fn jit_relocation_target_index(start,end,count,op,arg) {
    proof {jit_relocation_leaf_extent(start,end,count);}
    return jit_validate_branch_target(start,end,op,arg);
}

requires start>=0 && start<=268435440;
requires count>=2 && count<=8192;
requires end==start+count*16 && end<=268435456;
ensures end>start && (end-start)%16==0 && (end-start)/16==count;
lemma fn jit_relocation_leaf_extent(start,end,count) {
    let extent=end-start;
    assert extent==count*16;
    assert extent>=32 && extent<=131072;
    assert (extent&15)==0;
    assert extent%16==0;
    assert extent/16==extent>>4;
    assert ((count*16)>>4)==count;
}
