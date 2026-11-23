// Observer for three consecutive live slots in the production layout scan.
requires count>=3 && count<=16777216;
requires first>=0 && first<=count-3;
ensures first>=0 && first<=count-1;
ensures first+1>=0 && first+1<=count-1;
ensures first+2>=0 && first+2<=count-1;
ensures first<=16777213;
ensures first+1<count;
ensures first+2<count;
lemma fn io_layout_triple_indices(first,count) {
    assert first<=16777213;
    assert first+2>=0;
    assert first+2<count;
    assert first+2<=count-1;
    assert first+1<=count-1;
    assert first+1<count;
}



requires i>=0 && i<16777216;
requires first>=0 && first<=16777213;
ensures i-first>= -16777213 && i-first<=16777215;
ensures (i==first)==(i-first==0);
ensures (i==first+1)==(i-first==1);
ensures (i==first+2)==(i-first==2);
ensures (i>first)==(i-first>0);
ensures (i>first+1)==(i-first>1);
ensures (i>first+2)==(i-first>2);
ensures (i+1<=first)==((i-first)+1<=0);
ensures (i+1<=first+1)==((i-first)+1<=1);
ensures (i+1<=first+2)==((i-first)+1<=2);
ensures (i+1!=first+1)==((i-first)+1!=1);
ensures (i+1!=first+2)==((i-first)+1!=2);
lemma fn io_layout_triple_phase(i,first) {
    let phase=i-first;
    assert i==first+phase;
    assert phase>= -16777213 && phase<=16777215;
    io_layout_observed_crossing(i,first);
    io_layout_observed_crossing(i,first+1);
    io_layout_observed_crossing(i,first+2);
    assert (i<first)==(phase<0);
    assert (i<first+1)==(phase<1);
    assert (i<first+2)==(phase<2);
    assert (phase+1<=0)==(phase<0);
    assert (phase+1<=1)==(phase<1);
    assert (phase+1<=2)==(phase<2);
    assert (i+1!=first+1)==(i!=first);
    assert (i+1!=first+2)==(i!=first+1);
    assert (phase+1!=1)==(phase!=0);
    assert (phase+1!=2)==(phase!=1);
}

requires phase>= -16777213 && phase<=16777215;
requires prior>=0 && prior<=268435440 && (prior&15)==0;
requires (phase!=0) | (prior<=anchor_limit);
requires live==0 || live==1;
requires after==prior+live*16;
requires (phase<=0) | (a>=0 && (a&15)==0 && a<=anchor_limit);
requires (phase!=1) | (prior==a+16);
requires (phase!=2) | (prior==a+32);
requires (phase<=1) | (b==a+16);
requires (phase<=2) | (c==a+32);
requires (phase<=2) | (a+48<=prior);
requires (phase!=0) | ((aa==prior) & (live==1));
requires (phase!=1) | ((bb==prior) & (live==1));
requires (phase!=2) | ((cc==prior) & (live==1));
requires (phase<=0) | (aa==a);
requires (phase<=1) | (bb==b);
requires (phase<=2) | (cc==c);
ensures (phase+1<=0) | (aa>=0 && (aa&15)==0 && aa<=anchor_limit);
ensures (phase+1!=1) | (after==aa+16);
ensures (phase+1!=2) | (after==aa+32);
ensures (phase+1<=1) | (bb==aa+16);
ensures (phase+1<=2) | (cc==aa+32);
lemma fn io_layout_triple_step(phase,anchor_limit,prior,live,after,a,b,c,aa,bb,cc) {
    if phase<0 {assert phase+1<=0;}
    else if phase==0 {
        assert phase+1==1;
        assert aa==prior;
        assert after==aa+16;
    }else if phase==1 {
        assert phase+1==2;
        assert bb==prior;
        assert aa==a;
        assert bb==aa+16;
        assert after==aa+32;
    }else if phase==2 {
        assert phase+1==3;
        assert cc==prior;
        assert aa==a;
        assert cc==aa+32;
        assert after==aa+48;
    }else {
        assert phase>2;
        assert phase+1>2;
        assert aa==a && bb==b && cc==c;
        assert after>=prior;
    }
}

requires phase>= -16777213 && phase<=16777215;
requires prior>=0 && prior<=268435440;
requires live==0 || live==1;
requires after==prior+live*16;
requires (phase!=2) | ((prior==a+32) & (live==1));
requires (phase<=1) | (aa==a);
requires (phase<=2) | (a+48<=prior);
ensures (phase+1<=2) | (aa+48<=after);
lemma fn io_layout_triple_slack(phase,prior,live,after,a,aa) {
    if phase<2 {
        assert phase+1<=2;
    }else if phase==2 {
        assert aa==a;
        assert prior==aa+32;
        assert live==1;
        assert after==aa+48;
    }else {
        assert aa==a;
        assert aa+48==a+48;
        assert aa+48<=prior;
        assert after>=prior;
        assert aa+48<=after;
    }
}

requires count>=3 && count<=16777216;
requires first>=0 && first<=count-3;
ensures count-first>=3;
ensures first*16<=268435408;
lemma fn io_layout_triple_exit(first,count) {
    assert first<=16777213;
}

requires index>=0 && index<count && count<=16777216;
ensures count-(index+1)>=0;
ensures count-(index+1)<count-index;
lemma fn io_layout_rank_step(index,count) {}

requires at>=0 && at<=268435408;
requires size>=0 && size<=268435456;
requires at+48<=size;
ensures at<=size-48;
lemma fn io_layout_triple_fits(at,size) {}

requires value>=0 && value<=limit;
requires limit<=268435408;
ensures value>=0 && value<=268435408;
lemma fn io_layout_anchor_range(value,limit) {}

requires a==before_a && b==before_b && c==before_c;
requires before_a>=0 && (before_a&15)==0 && before_a<=size-48;
requires before_b==before_a+16 && before_c==before_a+32;
ensures a>=0 && (a&15)==0 && a<=size-48;
ensures b==a+16;
ensures c==a+32;
lemma fn io_layout_triple_preserved(a,b,c,before_a,before_b,before_c,size) {}

requires count>=3 && count<=16777216;
requires first>=0 && first<=count-3;
requires writable_bytes(io_map,(count+1)*8);
requires readable_bytes(io_flags,count);
requires disjoint_bytes(io_map,(count+1)*8,io_flags,count);
requires readable_bytes(io_map+(first)*8,8);
requires readable_bytes(io_flags+(first),1);
requires (load8(io_flags+(first))&1)==1;
requires readable_bytes(io_map+(first+1)*8,8);
requires readable_bytes(io_flags+(first+1),1);
requires (load8(io_flags+(first+1))&1)==1;
requires readable_bytes(io_map+(first+2)*8,8);
requires readable_bytes(io_flags+(first+2),1);
requires (load8(io_flags+(first+2))&1)==1;
modifies bytes(io_map,(count+1)*8);
ensures result==load64(io_map+count*8);
ensures result>=0;
ensures result<=count*16;
ensures (result&15)==0;
ensures load64(io_map+first*8)>=0;
ensures (load64(io_map+first*8)&15)==0;
ensures load64(io_map+first*8)<=result-48;
ensures load64(io_map+(first+1)*8)==load64(io_map+first*8)+16;
ensures load64(io_map+(first+2)*8)==load64(io_map+first*8)+32;
fn io_build_layout_live_triple(count,first) {
    let bytes=0;
    let i=0;
    proof {
        io_layout_triple_indices(first,count);
        io_layout_observed_flag(io_map,io_flags,count,first);
        io_layout_observed_flag(io_map,io_flags,count,first+1);
        io_layout_observed_flag(io_map,io_flags,count,first+2);
    }
    invariant i>=0 && i<=count;
    invariant bytes>=0;
    invariant bytes<=i*16;
    invariant (bytes&15)==0;
    invariant writable_bytes(io_map,(count+1)*8);
    invariant readable_bytes(io_flags,count);
    invariant (load8(io_flags+(first))&1)==1;
    invariant (load8(io_flags+(first+1))&1)==1;
    invariant (load8(io_flags+(first+2))&1)==1;
    invariant (i<=first) | (load64(io_map+first*8)>=0 && (load64(io_map+first*8)&15)==0 && load64(io_map+first*8)<=first*16);
    invariant (i!=first+1) | (bytes==load64(io_map+first*8)+16);
    invariant (i!=first+2) | (bytes==load64(io_map+first*8)+32);
    invariant (i<=first+1) | (load64(io_map+(first+1)*8)==load64(io_map+first*8)+16);
    invariant (i<=first+2) | (load64(io_map+(first+2)*8)==load64(io_map+first*8)+32);
    invariant (i<=first+2) | (load64(io_map+first*8)+48<=bytes);
    decreases count-i;
    while i<count {
        proof {
            io_layout_index(i,count);
            io_layout_region(io_map,io_flags,i,count);
            io_layout_progress(bytes,i,count);
        }
        ghost let prior=bytes;
        ghost let phase=i-first;
        ghost let before0=load64(io_map+(first)*8);
        ghost let before1=load64(io_map+(first+1)*8);
        ghost let before2=load64(io_map+(first+2)*8);
        proof {
            io_layout_triple_phase(i,first);
            io_layout_flag_separation(io_map,io_flags,count,i,first);
            if i>first {io_layout_previous_word(io_map,i,first,count);}
            io_layout_flag_separation(io_map,io_flags,count,i,first+1);
            if i>first+1 {io_layout_previous_word(io_map,i,first+1,count);}
            io_layout_flag_separation(io_map,io_flags,count,i,first+2);
            if i>first+2 {io_layout_previous_word(io_map,i,first+2,count);}
        }
        store64(io_map+i*8,bytes);
        let live=load8(io_flags+i)&1;
        proof {assert live==0 || live==1;}
        ghost let after0=load64(io_map+(first)*8);
        ghost let after1=load64(io_map+(first+1)*8);
        ghost let after2=load64(io_map+(first+2)*8);
        proof {
            io_layout_advance(bytes,i,count,live);
            if i==first {
                io_layout_observer_addresses(io_map,io_flags,i,first);
                io_layout_same_flag(io_flags+i,io_flags+(first));
                assert live==1;
                io_layout_same_word(io_map+i*8,io_map+(first)*8);
                assert after0==bytes;
            }
            if i>first {assert after0==before0;}
            if i==first+1 {
                io_layout_observer_addresses(io_map,io_flags,i,first+1);
                io_layout_same_flag(io_flags+i,io_flags+(first+1));
                assert live==1;
                io_layout_same_word(io_map+i*8,io_map+(first+1)*8);
                assert after1==bytes;
            }
            if i>first+1 {assert after1==before1;}
            if i==first+2 {
                io_layout_observer_addresses(io_map,io_flags,i,first+2);
                io_layout_same_flag(io_flags+i,io_flags+(first+2));
                assert live==1;
                io_layout_same_word(io_map+i*8,io_map+(first+2)*8);
                assert after2==bytes;
            }
            if i>first+2 {assert after2==before2;}
        }
        bytes=bytes+live*16;
        proof {
            assert prior<=268435440;
            if phase==0 {assert i==first;assert prior<=first*16;}
            io_layout_triple_step(phase,first*16,prior,live,bytes,before0,before1,before2,after0,after1,after2);
            io_layout_triple_slack(phase,prior,live,bytes,before0,after0);
            assert (i+1<=first) | (after0>=0 && (after0&15)==0 && after0<=first*16);
            assert (i+1!=first+1) | (bytes==after0+16);
            assert (i+1!=first+2) | (bytes==after0+32);
            assert (i+1<=first+1) | (after1==after0+16);
            assert (i+1<=first+2) | (after2==after0+32);
            assert (i+1<=first+2) | (after0+48<=bytes);
        }
        proof {
            assert bytes>=0;
            assert bytes<=(i+1)*16;
            assert (bytes&15)==0;
            io_layout_rank_step(i,count);
        }
        i=i+1;
    }
    proof {assert count*8>=0 && count*8+8==(count+1)*8;}
    ghost let a=load64(io_map+first*8);
    ghost let b=load64(io_map+(first+1)*8);
    ghost let c=load64(io_map+(first+2)*8);
    proof {
        assert i==count;
        io_layout_triple_indices(first,count);
        io_layout_triple_exit(first,count);
        assert i>first;
        assert i>first+1;
        assert i>first+2;
        assert a>=0;
        assert (a&15)==0;
        assert a<=first*16;
        io_layout_anchor_range(a,first*16);
        assert b==a+16;
        assert c==a+32;
        assert a+48<=bytes;
        io_layout_triple_fits(a,bytes);
        io_layout_previous_word(io_map,count,first,count);
        io_layout_previous_word(io_map,count,first+1,count);
        io_layout_previous_word(io_map,count,first+2,count);
    }
    store64(io_map+count*8,bytes);
    proof {
        assert load64(io_map+first*8)==a;
        assert load64(io_map+(first+1)*8)==b;
        assert load64(io_map+(first+2)*8)==c;
        io_layout_triple_preserved(load64(io_map+first*8),load64(io_map+(first+1)*8),
                                   load64(io_map+(first+2)*8),a,b,c,bytes);
    }
    return bytes;
}
