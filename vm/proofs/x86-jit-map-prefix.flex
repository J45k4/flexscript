// The immutable offsets table supplies the output cursor that emission has
// at each body slot. The projection checks map writes and their progression.
global vm_jit_map=0;

requires start>=0 && start<=67108864;
requires end==start+map_count*16 && end<=67108864;
requires map_count>=1 && map_count<=8192;
requires observed>=1 && observed<map_count;
requires writable_bytes(vm_jit_map,8193*8);
requires readable_bytes(offsets,8193*8);
requires disjoint_bytes(vm_jit_map,8193*8,offsets,8193*8);
requires readable_bytes(vm_jit_map+observed*8,8);
requires readable_bytes(offsets+observed*8,8);
requires disjoint_bytes(vm_jit_map,8193*8,offsets+observed*8,8);
modifies bytes(vm_jit_map,8193*8);
ensures result==map_count;
ensures load64(vm_jit_map+observed*8)==old(load64(offsets+observed*8));
fn jit_record_map_prefix(start,end,map_count,offsets,observed) {
    let pc=start;
PRODUCTION_MAP_PROLOGUE
    ghost let wanted=load64(offsets+observed*8);
    invariant map_slot>=1 && map_slot<=map_count;
    invariant load64(offsets+observed*8)==wanted;
    invariant (map_slot<=observed) | (load64(vm_jit_map+observed*8)==wanted);
    decreases map_count-map_slot;
PRODUCTION_MAP_LOOP
PRODUCTION_MAP_PC
        proof {
            jit_emission_pc_for_slot(start,end,map_slot,map_count);
            assert pc==start+map_slot*16 && pc>=start+16 && pc+16<=end;
            jit_record_map_rank(map_slot,map_count);
            jit_record_map_subspans(vm_jit_map,offsets,map_slot,observed);
            assert disjoint_bytes(vm_jit_map+map_slot*8,8,offsets+observed*8,8);
        }
        let output_size=load64(offsets+map_slot*8);
        proof {
            if map_slot==observed {
                jit_record_map_equal_word(offsets+map_slot*8,offsets+observed*8);
                assert output_size==wanted;
                jit_record_map_alias(vm_jit_map,map_slot,observed);
            }
            if map_slot>observed {
                jit_record_map_ordered_words(vm_jit_map,observed,map_slot);
                assert disjoint_bytes(vm_jit_map+map_slot*8,8,vm_jit_map+observed*8,8);
            }
        }
        ghost let previous=load64(vm_jit_map+observed*8);
PRODUCTION_MAP_RECORD
        ghost let current=load64(vm_jit_map+observed*8);
        proof {
            assert load64(offsets+observed*8)==wanted;
            if map_slot==observed {assert current==wanted;}
            if map_slot>observed {
                assert previous==wanted;
                assert current==previous;
            }
            jit_record_map_content_step(map_slot,observed,previous,current,wanted);
        }
PRODUCTION_MAP_ADVANCE
    }
    proof {jit_record_map_done(map_count,map_slot,observed);}
    return map_slot;
}

requires count>=1 && count<=8192;
requires slot>=1 && slot<count;
ensures slot+1<=count && slot+1>=1;
ensures count-(slot+1)>=0 && count-(slot+1)<count-slot;
lemma fn jit_record_map_rank(slot,count) {
    assert slot+1<=count;
    assert count-(slot+1)==count-slot-1;
}

requires slot>=1 && slot<=count;
requires slot>=count && observed<count;
ensures slot==count && slot>observed;
lemma fn jit_record_map_done(count,slot,observed) {
    assert slot==count;
}

requires slot>=1 && slot<=8191;
requires observed>=1 && observed<=8191;
requires writable_bytes(map,8193*8);
requires readable_bytes(offsets,8193*8);
requires readable_bytes(offsets+observed*8,8);
requires disjoint_bytes(map,8193*8,offsets+observed*8,8);
ensures writable_bytes(map+slot*8,8);
ensures readable_bytes(offsets+slot*8,8);
ensures disjoint_bytes(map+slot*8,8,offsets+observed*8,8);
lemma fn jit_record_map_subspans(map,offsets,slot,observed) {
    assert slot*8>=8 && slot*8<=8192*8;
}

requires earlier>=1 && earlier<later && later<=8191;
requires writable_bytes(map,8193*8);
ensures disjoint_bytes(map+later*8,8,map+earlier*8,8);
lemma fn jit_record_map_ordered_words(map,earlier,later) {
    assert earlier*8>=8 && earlier*8<=8192*8;
    assert later*8>=8 && later*8<=8192*8;
    assert writable_bytes(map+earlier*8,8);
    assert writable_bytes(map+later*8,8);
    assert (map+later*8)-(map+earlier*8)==(later-earlier)*8;
    assert (later-earlier)*8>=8;
}

requires slot==observed;
ensures map+slot*8==map+observed*8;
lemma fn jit_record_map_alias(map,slot,observed) {}

requires first==second;
requires readable_bytes(first,8) && readable_bytes(second,8);
ensures load64(first)==load64(second);
lemma fn jit_record_map_equal_word(first,second) {}

requires slot>=1 && slot<observed && observed<=8191;
ensures slot+1<=observed;
lemma fn jit_record_map_before_observation(slot,observed) {}

requires slot>=1 && slot<=8191 && observed>=1 && observed<=8191;
requires slot!=observed || current==wanted;
requires slot<=observed || previous==wanted;
requires slot<=observed || current==previous;
ensures (slot+1<=observed) | (current==wanted);
lemma fn jit_record_map_content_step(slot,observed,previous,current,wanted) {
    if slot<observed {jit_record_map_before_observation(slot,observed);return 0;}
    if slot==observed {assert current==wanted;return 0;}
    assert current==previous && previous==wanted;
}


requires start>=0 && start<=67108864;
requires count>=1 && count<=8192;
requires end==start+count*16 && end<=67108864;
requires slot>=1 && slot<count;
ensures start+slot*16>=start+16;
ensures start+slot*16<end;
ensures start+slot*16+16<=end;
ensures ((start+slot*16)-start)/16==slot;
lemma fn jit_emission_pc_for_slot(start,end,slot,count) {
    assert slot*16>=16;
    assert slot*16<count*16;
    assert slot*16<=131072 && count*16<=131072;
    jit_record_map_offset_order(start,slot*16,count*16,start+slot*16,end);
    assert slot+1<=count;
    assert (slot+1)*16<=count*16;
    assert (slot+1)*16==slot*16+16;
    assert ((start+slot*16)-start)==slot*16;
    assert (slot*16)/16==slot;
}

requires base>=0 && base<=67108864;
requires pos>=16 && pos<limit && limit<=131072;
requires actual==base+pos && end==base+limit;
ensures actual>=base+16;
ensures actual<end;
lemma fn jit_record_map_offset_order(base,pos,limit,actual,end) {
    assert actual>=base+16;
    assert base+pos<base+limit;
}
