// A selected live call, observed across the prefix, copy, and suffix of the
// production relocation loop. Used with the loop and single-step proof profiles.

requires earlier>0 && earlier<=0x7fffffffffffffe0;
requires later>0 && later<=0x7fffffffffffffe0;
requires later-earlier>=32;
ensures disjoint_bytes(earlier,32,later,32);
ensures disjoint_bytes(later,32,earlier,32);
lemma fn record_table_ordered_spans(earlier,later) {
    assert later>earlier;
}

requires lower>=0 && lower<count;
requires higher>=0 && higher<count;
requires lower<higher && count<=65536;
requires writable_bytes(base,count*32);
ensures disjoint_bytes(base+lower*32,32,base+higher*32,32);
ensures disjoint_bytes(base+higher*32,32,base+lower*32,32);
lemma fn record_table_two_slots(base,count,lower,higher) {
    record_table_address(base,lower,count);
    record_table_address(base,higher,count);
    record_table_ordered_offsets(lower,higher);
    let a=base+lower*32;
    let b=base+higher*32;
    assert b-a==higher*32-lower*32;
    record_table_ordered_spans(a,b);
}

requires field==0 || field==8 || field==16 || field==24;
requires disjoint_bytes(writer,32,observed,32);
ensures disjoint_bytes(writer,32,observed+field,8);
ensures disjoint_bytes(writer+16,8,observed+field,8);
lemma fn record_table_disjoint_field(writer,observed,field) {
    if field==0 {assert field==0;return 0;}
    if field==8 {assert field==8;return 0;}
    if field==16 {assert field==16;return 0;}
    assert field==24;
}

requires i>=0 && i<watch;
requires watch<call_count && call_count<=65536;
ensures i<call_count;
ensures call_count>=1;
lemma fn record_table_prefix_cursor(i,watch,call_count) {
    assert watch<=65535;
    assert i<=65534;
}

requires count>=0 && count<=16777216;
requires call_count>=0 && call_count<=65536;
requires writable_bytes(calls,call_count*32);
requires readable_bytes(io_flags,count);
requires readable_bytes(io_map,(count+1)*8);
requires watch>=0 && watch<call_count;
requires readable_bytes(calls+watch*32+16,8);
modifies bytes(calls,call_count*32);
ensures result==-1 || (result>=0 && result<=watch);
ensures output_size==old(output_size);
ensures load64(calls+watch*32+16)==old(load64(calls+watch*32+16));
fn io_relocate_prefix_preserves_original_call_pc(count,watch) {
    ghost let original_pc=load64(calls+watch*32+16);
    let calls_used=0;
    let i=0;
    invariant i>=0 && i<=watch;
    invariant calls_used>=0 && calls_used<=i;
    invariant writable_bytes(calls,call_count*32);
    invariant readable_bytes(io_flags,count);
    invariant readable_bytes(io_map,(count+1)*8);
    invariant readable_bytes(calls+watch*32+16,8);
    invariant load64(calls+watch*32+16)==original_pc;
    decreases watch-i;
    while i<watch {
        proof {
            record_table_prefix_cursor(i,watch,call_count);
            io_relocation_used_in_table(calls_used,i,call_count);
            io_relocation_cursor_step(i,calls_used,call_count);
            io_call_table_record_offset(i,call_count);
            io_call_table_record_offset(calls_used,call_count);
            io_call_table_record_permissions(calls,i,call_count);
            io_call_table_record_permissions(calls,calls_used,call_count);
            assert i*32+16>=0 && i*32+16<=call_count*32-8;
            assert calls_used*32>=0 && calls_used*32<=call_count*32-32;
        }
        let updated=io_relocate_guarded_call(count,i,calls_used);
        proof {
            record_table_used_is_before_watch(calls_used,i,watch);
            record_table_untouched_later_pc(calls,call_count,i,watch);
            record_table_untouched_later_pc(calls,call_count,calls_used,watch);
            assert disjoint_bytes(calls+i*32+16,8,calls+watch*32+16,8);
            assert disjoint_bytes(calls+calls_used*32,32,calls+watch*32+16,8);
            assert load64(calls+watch*32+16)==original_pc;
        }
        if updated<0 {return -1;}
        proof {record_table_loop_advance(watch,i,updated);}
        calls_used=updated;
        i=i+1;
    }
    proof {record_table_loop_count(calls_used,i,watch);}
    return calls_used;
}

requires watch>=0 && watch<used;
requires used<=i && i<65536;
ensures watch<i;
lemma fn record_table_compacted_before_iteration(watch,used,i) {
    assert used<=65535;
    assert watch<=65534;
}

requires watch>=0 && watch<used_at_start;
requires used_at_start<=current;
requires current<=updated && updated<=65536;
ensures updated>watch;
ensures updated>=used_at_start;
lemma fn record_table_compacted_count_advances(watch,used_at_start,current,updated) {
    assert watch<=65535;
    assert used_at_start<=65536;
    assert current<=65536;
}

requires count>=0 && count<=16777216;
requires call_count>=0 && call_count<=65536;
requires writable_bytes(calls,call_count*32);
requires readable_bytes(io_flags,count);
requires readable_bytes(io_map,(count+1)*8);
requires watch>=0 && watch<used_at_start;
requires watch<call_count;
requires used_at_start<=start && start<=call_count;
requires readable_bytes(calls+watch*32+16,8);
modifies bytes(calls,call_count*32);
ensures load64(calls+watch*32+16)==old(load64(calls+watch*32+16));
ensures result==-1 || (result>=used_at_start && result<=call_count);
ensures output_size==old(output_size);
fn io_relocate_preserves_compacted_call(count,start,used_at_start,watch) {
    ghost let original=load64(calls+watch*32+16);
    let calls_used=used_at_start;
    let i=start;
    invariant i>=0 && i<=call_count;
    invariant calls_used>=used_at_start && calls_used<=i;
    invariant watch<calls_used;
    invariant writable_bytes(calls,call_count*32);
    invariant readable_bytes(io_flags,count);
    invariant readable_bytes(io_map,(count+1)*8);
    invariant readable_bytes(calls+watch*32+16,8);
    invariant load64(calls+watch*32+16)==original;
    decreases call_count-i;
    while i<call_count {
        proof {
            assert call_count>=1;
            io_relocation_used_in_table(calls_used,i,call_count);
            io_relocation_cursor_step(i,calls_used,call_count);
            io_call_table_record_offset(i,call_count);
            io_call_table_record_offset(calls_used,call_count);
            io_call_table_record_permissions(calls,i,call_count);
            io_call_table_record_permissions(calls,calls_used,call_count);
            assert i*32+16>=0 && i*32+16<=call_count*32-8;
            assert calls_used*32>=0 && calls_used*32<=call_count*32-32;
        }
        let updated=io_relocate_guarded_call(count,i,calls_used);
        proof {
            record_table_compacted_before_iteration(watch,calls_used,i);
            record_table_two_slots(calls,call_count,watch,i);
            record_table_two_slots(calls,call_count,watch,calls_used);
            record_table_disjoint_field(calls+i*32,calls+watch*32,16);
            record_table_disjoint_field(calls+calls_used*32,calls+watch*32,16);
            assert disjoint_bytes(calls+i*32+16,8,calls+watch*32+16,8);
            assert disjoint_bytes(calls+calls_used*32,32,calls+watch*32+16,8);
            assert load64(calls+watch*32+16)==original;
        }
        if updated<0 {return -1;}
        proof {
            record_table_loop_advance(call_count,i,updated);
            assert updated>=calls_used;
            record_table_compacted_count_advances(watch,used_at_start,calls_used,updated);
        }
        calls_used=updated;
        i=i+1;
    }
    proof {record_table_loop_count(calls_used,i,call_count);}
    return calls_used;
}

requires rank>=0 && rank<=watch;
requires watch<call_count && call_count<=65536;
requires next==rank+1;
ensures rank<next;
ensures next<=watch+1;
ensures watch+1<=call_count;
lemma fn record_table_selected_successor(rank,watch,call_count,next) {
    assert rank<=65535;
    assert watch<=65535;
}

requires count>=1 && count<=16777216;
requires pc>=0 && pc<=count*16-16;
ensures pc<=268435440;
lemma fn record_table_observed_pc_bound(pc,count) {
    assert count*16<=268435456;
}

requires count>=1 && count<=65536;
requires index>=0 && index<count;
requires writable_bytes(table,count*32);
requires disjoint_bytes(table,count*32,watched,8);
ensures disjoint_bytes(table+index*32,32,watched,8);
ensures disjoint_bytes(table+index*32+16,8,watched,8);
lemma fn record_table_keeps_word(table,count,index,watched) {
    io_call_table_record_offset(index,count);
    assert index*32+16>=0 && index*32+16<=count*32-8;
}

requires count>=1 && count<=65536;
requires index>=0 && index<count;
requires writable_bytes(table,count*32);
requires disjoint_bytes(table,count*32,watched,1);
ensures disjoint_bytes(table+index*32,32,watched,1);
ensures disjoint_bytes(table+index*32+16,8,watched,1);
lemma fn record_table_keeps_flag(table,count,index,watched) {
    io_call_table_record_offset(index,count);
    assert index*32+16>=0 && index*32+16<=count*32-8;
}

requires count>=1 && count<=65536;
requires used>=0 && used<=i && i<count;
requires writable_bytes(table,count*32);
ensures table+used*32<=table+i*32;
ensures used==i || disjoint_bytes(table+used*32,32,table+i*32,32);
lemma fn record_table_destination_order(table,count,used,i) {
    record_table_address(table,used,count);
    record_table_address(table,i,count);
    if used<i {
        record_table_two_slots(table,count,used,i);
        record_table_ordered_offsets(used,i);
        assert (table+i*32)-(table+used*32)==i*32-used*32;
        assert (table+i*32)-(table+used*32)>=32;
    }
}

requires count>=1 && count<=16777216;
requires call_count>=1 && call_count<=65536;
requires watch>=0 && watch<call_count;
requires byte>=0 && byte<8;
requires pc>=0 && pc<=count*16-16 && (pc&15)==0;
requires writable_bytes(calls,call_count*32);
requires readable_bytes(calls+watch*32+16,8);
requires load64(calls+watch*32+16)==pc+8;
requires readable_bytes(io_flags,count);
requires readable_bytes(io_map,(count+1)*8);
requires readable_bytes(io_flags+pc/16,1);
requires readable_bytes(io_map+pc/2,8);
requires (load8(io_flags+pc/16)&1)==1;
requires load64(io_map+pc/2)==mapped_pc;
requires disjoint_bytes(calls,call_count*32,io_flags+pc/16,1);
requires disjoint_bytes(calls,call_count*32,io_map+pc/2,8);
modifies bytes(calls,call_count*32);
ensures result==-1 || (result>=0 && result<=watch);
ensures result==-1 || load8(calls+result*32+16+byte)==(((mapped_pc+8)>>(byte*8))&255);
ensures output_size==old(output_size);
fn io_relocate_selected_live_pc_byte(count,watch,pc,mapped_pc,byte) {
    let rank=io_relocate_prefix_preserves_original_call_pc(count,watch);
    if rank<0 {return -1;}
    let flag=io_flags+pc/16;
    let map_word=io_map+pc/2;
    let input_pc=calls+watch*32+16;
    let destination_pc=calls+rank*32+16;
    proof {
        assert rank>=0 && rank<=watch;
        io_relocation_used_in_table(rank,watch,call_count);
        io_relocation_cursor_step(watch,rank,call_count);
        io_call_table_record_offset(watch,call_count);
        io_call_table_record_offset(rank,call_count);
        assert watch*32+16>=0 && watch*32+16<=call_count*32-8;
        record_table_observed_pc_bound(pc,count);
        assert load64(input_pc)==pc+8;
        assert (load8(flag)&1)==1;
        assert load64(map_word)==mapped_pc;
        io_call_table_record_permissions(calls,watch,call_count);
        io_call_table_record_permissions(calls,rank,call_count);
        record_table_destination_order(calls,call_count,rank,watch);
        record_table_keeps_flag(calls,call_count,watch,flag);
        record_table_keeps_flag(calls,call_count,rank,flag);
        record_table_keeps_word(calls,call_count,watch,map_word);
        record_table_keeps_word(calls,call_count,rank,map_word);
        assert byte+16>=16 && byte+16<24;
    }
    let next=io_call_relocation_step(watch,rank,pc,mapped_pc,byte+16,1,count,map_word);
    ghost let written=load64(destination_pc);
    proof {
        assert next==rank+1;
        record_table_selected_successor(rank,watch,call_count,next);
        assert load8(destination_pc+byte)==(((mapped_pc+8)>>(byte*8))&255);
        call_record_word_byte(destination_pc,byte);
    }
    proof {
        assert rank>=0 && rank<next;
        assert rank<call_count;
        assert next<=watch+1 && watch+1<=call_count;
        assert readable_bytes(calls+rank*32+16,8);
    }
    let retained=io_relocate_preserves_compacted_call(count,watch+1,next,rank);
    if retained<0 {return -1;}
    proof {
        assert load64(destination_pc)==written;
        call_record_word_byte(destination_pc,byte);
        assert load8(destination_pc+byte)==(((mapped_pc+8)>>(byte*8))&255);
    }
    return rank;
}
