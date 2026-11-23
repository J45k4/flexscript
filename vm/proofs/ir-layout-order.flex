requires index>=0 && index<16777216;
requires first>=0 && first<later && later<16777216;
requires (index<=later) | (a<b);
requires (index<=first) | (a==a_after);
requires (index<=later) | (b==b_after);
requires (index!=later) | ((a_after<bytes) & (b_after==bytes));
ensures (index+1<=later) | (a_after<b_after);
lemma fn io_layout_order_induction(index,first,later,a,b,a_after,b_after,bytes) {
    io_layout_observed_crossing(index,later);
    if index>later {
        assert index>first;
        assert a_after==a;
        assert b_after==b;
    }
}

requires index>observe;
requires (index<=observe) | (before<cursor);
requires after==before;
ensures after<cursor;
lemma fn io_layout_seen_less(index,observe,before,after,cursor) {}

requires low<middle && middle<=high;
ensures low<high;
lemma fn io_layout_cursor_monotone(low,middle,high) {}

requires index>=0 && index<count && count<=16777216;
ensures count-(index+1)>=0;
ensures count-(index+1)<count-index;
lemma fn io_layout_rank_step(index,count) {}

requires a==before_a && b==before_b;
requires before_a<before_b;
ensures a<b;
lemma fn io_layout_order_preserved(a,b,before_a,before_b) {}

requires observe<later;
requires i==later;
ensures i>observe;
lemma fn io_layout_second_follows_first(i,observe,later) {}

// Any live input slot receives a strictly smaller offset than each later
// slot. The proof gate inserts the production body and erased annotations.
requires count>=1 && count<=16777216;
requires observe>=0 && observe<count;
requires later>observe && later<count;
requires writable_bytes(io_map,(count+1)*8);
requires readable_bytes(io_flags,count);
requires disjoint_bytes(io_map,(count+1)*8,io_flags,count);
requires readable_bytes(io_map+observe*8,8);
requires readable_bytes(io_map+later*8,8);
requires readable_bytes(io_flags+observe,1);
requires (load8(io_flags+observe)&1)==1;
modifies bytes(io_map,(count+1)*8);
ensures result>=0 && result<=count*16 && (result&15)==0;
ensures load64(io_map+count*8)==result;
ensures load64(io_map+observe*8)<load64(io_map+later*8);
fn io_build_layout_ordered(count,observe,later) {
    // Production ordered layout body.

}
