// Safety and termination of the bounded production call-record loop.
import "../../compiler/ir-layout.flex";

PRODUCTION_CALL_GLOBALS
PRODUCTION_LIVE_BIT

requires n==32;
requires readable_bytes(from,n);
requires writable_bytes(to,n);
reads bytes(from,n);
modifies bytes(to,n);
ensures result==0;
fn net_copy(to,from,n) {let i=0;
    invariant i>=0 && i<=n;
    invariant readable_bytes(from,n);
    invariant writable_bytes(to,n);
    decreases n-i;
    while i<n {PRODUCTION_BYTE_COPYi=i+1;}return 0;}

requires count>=1 && count<=65536;
requires index>=0 && index<count;
ensures index*32>=0 && index*32<=count*32-32;
lemma fn io_call_table_record_offset(index,count) {
    assert index<=65535;
    assert index+1<=count;
    assert index*32+32==(index+1)*32;
    assert (index+1)*32<=count*32;
    assert count*32-32>=0;
}

requires count>=1 && count<=65536;
requires index>=0 && index<count;
requires writable_bytes(table,count*32);
ensures writable_bytes(table+index*32,32);
ensures writable_bytes(table+index*32+16,8);
lemma fn io_call_table_record_permissions(table,index,count) {
    io_call_table_record_offset(index,count);
    assert index*32+16>=0 && index*32+16<=count*32-8;
}


requires count>=1 && count<=16777216;
requires slot>=0 && slot<=count-1;
requires readable_bytes(flags,count);
ensures readable_bytes(flags+slot,1);
lemma fn io_relocation_flag_span(flags,slot,count) {}

requires count>=1 && count<=16777216;
requires offset>=0 && offset<=count*8-8;
requires readable_bytes(map,(count+1)*8);
ensures readable_bytes(map+offset,8);
lemma fn io_relocation_map_span(map,offset,count) {
    assert (count+1)*8-8==count*8;
    assert offset<=(count+1)*8-8;
}

requires count>=1 && count<=16777216;
requires at>=0 && at<=count*16-16 && (at&15)==0;
requires readable_bytes(flags,count);
requires readable_bytes(map,(count+1)*8);
ensures readable_bytes(flags+at/16,1);
ensures readable_bytes(map+at/2,8);
lemma fn io_relocation_site_permissions(flags,map,at,count) {
    assert at<=268435440;
    assert at/16>=0 && at/16<=count-1;
    io_relocation_flag_span(flags,at/16,count);
    assert at/2>=0 && at/2<=count*8-8;
    io_relocation_map_span(map,at/2,count);
}
requires i>=0 && i<count && count<=65536;
requires used>=0 && used<=i;
ensures i+1>=0 && i+1<=count;
ensures used+1>=0 && used+1<=i+1;
lemma fn io_relocation_cursor_step(i,used,count) {
    assert i<=65535;
    assert used<=65535;
    assert i+1<=count;
    assert used+1<=i+1;
}
requires used>=0 && used<=i;
requires i>=0 && i<count && count<=65536;
ensures used<count;
lemma fn io_relocation_used_in_table(used,i,count) {
    io_relocation_cursor_step(i,used,count);
    assert used+1<=count;
}


requires count>=0 && count<=16777216;
requires call_count>=1 && call_count<=65536;
requires i>=0 && i<call_count;
requires calls_used>=0 && calls_used<=i && calls_used<call_count;
requires writable_bytes(calls,call_count*32);
requires readable_bytes(io_flags,count);
requires readable_bytes(io_map,(count+1)*8);
requires writable_bytes(calls+i*32+16,8);
requires writable_bytes(calls+calls_used*32,32);
modifies bytes(calls+i*32+16,8),bytes(calls+calls_used*32,32);
ensures result==-1 || result==old(calls_used) || result==old(calls_used)+1;
ensures result==-1 || (result>=0 && result<=i+1);
fn io_relocate_guarded_call(count,i,calls_used) {
    let size=count*16;
    proof {
        io_call_table_record_offset(i,call_count);
        io_call_table_record_offset(calls_used,call_count);
        io_call_table_record_permissions(calls,i,call_count);
        io_call_table_record_permissions(calls,calls_used,call_count);
        io_relocation_cursor_step(i,calls_used,call_count);
        assert i*32+16>=0 && i*32+16<=call_count*32-8;
    }
    let c=calls+i*32;
    let at=load64(c+16)-8;
    if at<0 || at>size-16 || (at&15) {return -1;}
    proof {
        assert count>=1;
        io_relocation_site_permissions(io_flags,io_map,at,count);
    }
    if io_live(at) {
        store64(c+16,load64(io_map+at/2)+8);
        net_copy(calls+calls_used*32,c,32);
        return calls_used+1;
    }
    return calls_used;
}

requires count>=0 && count<=16777216;
requires call_count>=0 && call_count<=65536;
requires writable_bytes(calls,call_count*32);
requires readable_bytes(io_flags,count);
requires readable_bytes(io_map,(count+1)*8);
modifies bytes(calls,call_count*32);
ensures result==-1 || (result>=0 && result<=call_count);
ensures output_size==old(output_size);
fn io_relocate_guarded_calls(count) {
    let calls_used=0;
    let i=0;
    invariant i>=0 && i<=call_count;
    invariant calls_used>=0 && calls_used<=i;
    invariant writable_bytes(calls,call_count*32);
    invariant readable_bytes(io_flags,count);
    invariant readable_bytes(io_map,(count+1)*8);
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
        if updated<0 {return -1;}
        calls_used=updated;
        i=i+1;
    }
    return calls_used;
}

requires index>=0 && index<count && count<=65536;
requires writable_bytes(base,count*32);
ensures base+index*32>0 && base+index*32<=0x7fffffffffffffe0;
lemma fn record_table_address(base,index,count) {
    io_call_table_record_offset(index,count);
    assert writable_bytes(base+index*32,32);
}

requires lower>=0 && higher>=0 && lower<higher && higher<65536;
ensures higher*32-lower*32>=32;
lemma fn record_table_ordered_offsets(lower,higher) {
    assert higher-lower>=1 && higher-lower<=65535;
    assert higher*32-lower*32==(higher-lower)*32;
    assert (higher-lower)*32>=32;
}


requires earlier>0 && earlier<=0x7fffffffffffffe0;
requires later>0 && later<=0x7fffffffffffffe0;
requires distance>=32 && distance<=2097120;
requires later-earlier==distance;
ensures disjoint_bytes(earlier,32,later+16,8);
ensures disjoint_bytes(earlier+16,8,later+16,8);
lemma fn record_table_later_pc_separation(earlier,later,distance) {
    assert earlier+16>0 && earlier+16<=0x7ffffffffffffff8;
    assert later+16>0 && later+16<=0x7ffffffffffffff8;
    assert distance+16>=48;
    assert (later+16)-(earlier+16)==distance;
}

requires earlier>=0 && earlier<count;
requires later>=0 && later<count;
requires earlier<later && count<=65536;
requires writable_bytes(table,count*32);
ensures disjoint_bytes(table+earlier*32,32,table+later*32+16,8);
ensures disjoint_bytes(table+earlier*32+16,8,table+later*32+16,8);
lemma fn record_table_untouched_later_pc(table,count,earlier,later) {
    record_table_address(table,earlier,count);
    record_table_address(table,later,count);
    record_table_ordered_offsets(earlier,later);
    let from=table+earlier*32;
    let to=table+later*32;
    let distance=later*32-earlier*32;
    assert to-from==distance;
    assert later<=65535;
    assert later*32<=2097120;
    assert earlier*32>=0;
    assert distance<=2097120;
    record_table_later_pc_separation(from,to,distance);
}

requires used>=0 && used<=i;
requires i>=0 && i<watch && watch<65536;
ensures used<watch;
lemma fn record_table_used_is_before_watch(used,i,watch) {
    assert i<=65534;
    assert used<=65534;
    assert used<=watch-1;
}


requires count>=1 && count<=65536;
requires index>=0 && index<count;
requires updated>=0 && updated<=index+1;
ensures index+1>=0 && index+1<=count;
ensures updated<=index+1;
ensures count-(index+1)<count-index;
lemma fn record_table_loop_advance(count,index,updated) {
    assert index+1<=count;
    assert count-(index+1)+1==count-index;
    assert count-(index+1)>=0;
}

requires i>=0 && i<=count && count<=65536;
requires used>=0 && used<=i;
ensures used>=0 && used<=count;
lemma fn record_table_loop_count(used,i,count) {
    assert i<=65536;
    assert used<=65536;
}

requires count>=0 && count<=16777216;
requires call_count>=0 && call_count<=65536;
requires writable_bytes(calls,call_count*32);
requires readable_bytes(io_flags,count);
requires readable_bytes(io_map,(count+1)*8);
requires watch>=0 && watch<call_count;
requires readable_bytes(calls+watch*32+16,8);
modifies bytes(calls,call_count*32);
ensures result==-1 || (result>=0 && result<=call_count);
ensures output_size==old(output_size);
fn io_relocate_observes_original_call_pc(count,watch) {
    ghost let original_pc=load64(calls+watch*32+16);
    let calls_used=0;
    let i=0;
    invariant i>=0 && i<=call_count;
    invariant calls_used>=0 && calls_used<=i;
    invariant writable_bytes(calls,call_count*32);
    invariant readable_bytes(io_flags,count);
    invariant readable_bytes(io_map,(count+1)*8);
    invariant readable_bytes(calls+watch*32+16,8);
    invariant i>watch || load64(calls+watch*32+16)==original_pc;
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
        proof {
            if i==watch {assert load64(calls+watch*32+16)==original_pc;}
        }
        let updated=io_relocate_guarded_call(count,i,calls_used);
        if updated<0 {return -1;}
        proof {record_table_loop_advance(call_count,i,updated);}
        proof {
            if i+1<=watch {
                assert i<watch;
                record_table_used_is_before_watch(calls_used,i,watch);
                record_table_untouched_later_pc(calls,call_count,i,watch);
                record_table_untouched_later_pc(calls,call_count,calls_used,watch);
                assert disjoint_bytes(calls+i*32+16,8,calls+watch*32+16,8);
                assert disjoint_bytes(calls+calls_used*32,32,calls+watch*32+16,8);
                assert load64(calls+watch*32+16)==original_pc;
            }
        }
        calls_used=updated;
        i=i+1;
    }
    proof {record_table_loop_count(calls_used,i,call_count);}
    return calls_used;
}
