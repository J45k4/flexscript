// One guarded optimizer call-record iteration, with an arbitrary observed byte and disjoint word.
import "../../compiler/ir-layout.flex";

PRODUCTION_CALL_GLOBALS
PRODUCTION_LIVE_BIT

requires address==other;
requires readable_bytes(address,1);
ensures load8(address)==load8(other);
lemma fn copy_record_same_byte(address,other) {}

requires earlier>0 && later>earlier;
ensures disjoint_bytes(earlier,1,later,1);
lemma fn copy_record_ordered_bytes(earlier,later) {
    assert later>0;
    assert earlier!=later;
}

requires from>to;
requires i>=0 && i<32 && observe>=0 && observe<32;
requires disjoint_bytes(to,32,from,32);
ensures disjoint_bytes(to+i,1,from+observe,1);
lemma fn copy_record_separate_source(to,from,i,observe) {
    assert to>0 && to<=0x7fffffffffffffe0;
    assert from>0 && from<=0x7fffffffffffffe0;
    assert from-to>=32;
    assert from>to+31;
    assert to+i>=to && to+i<=to+31;
    assert from+observe>=from && from+observe<=from+31;
    assert to+i<from+observe;
    copy_record_ordered_bytes(to+i,from+observe);
}

requires i>=0 && i<32 && observe>=0 && observe<32 && i!=observe;
requires writable_bytes(base,32);
ensures disjoint_bytes(base+i,1,base+observe,1);
lemma fn copy_record_separate_bytes(base,i,observe) {
    assert base+i!=base+observe;
}

requires i>=0 && i<32 && observe>=0 && observe<32 && i!=observe;
requires writable_bytes(to,32);
requires to<=from;
requires to==from || disjoint_bytes(to,32,from,32);
ensures disjoint_bytes(to+i,1,from+observe,1);
lemma fn copy_record_source_untouched(to,from,i,observe) {
    if to==from {
        copy_record_separate_bytes(to,i,observe);
        assert from+observe==to+observe;
    }else {
        copy_record_separate_source(to,from,i,observe);
    }
}

requires i>=0 && i<32 && observe>=0 && observe<32;
requires (i>=observe) | (after_source==original);
requires (i<observe) | (after_dest==original);
ensures (i+1>observe) | (after_source==original);
ensures (i+1<=observe) | (after_dest==original);
lemma fn copy_record_observation_step(i,observe,after_source,after_dest,original) {}

requires n==32;
requires observe>=0 && observe<n;
requires writable_bytes(to,n);
requires readable_bytes(from,n);
requires to<=from;
requires to==from || disjoint_bytes(to,n,from,n);
modifies bytes(to,n);
ensures result==0;
ensures load8(to+observe)==old(load8(from+observe));
fn net_copy_call_record(to,from,n,observe) {
    ghost let original=load8(from+observe);
    let i=0;
    invariant i>=0 && i<=n;
    invariant writable_bytes(to,n);
    invariant readable_bytes(from,n);
    invariant (i>observe) | (load8(from+observe)==original);
    invariant (i<=observe) | (load8(to+observe)==original);
    decreases n-i;
    while i<n {
        ghost let before_source=load8(from+observe);
        ghost let before_dest=load8(to+observe);
        ghost let copied=load8(from+i);
        proof {
            assert writable_bytes(to+i,1);
            assert readable_bytes(from+i,1);
            if i<observe {
                copy_record_source_untouched(to,from,i,observe);
                assert before_source==original;
            }
            if i==observe {
                copy_record_same_byte(from+observe,from+i);
                assert copied==before_source;
            }
            if i>observe {
                copy_record_separate_bytes(to,i,observe);
                assert before_dest==original;
            }
        }
        PRODUCTION_BYTE_COPY
        ghost let after_source=load8(from+observe);
        ghost let after_dest=load8(to+observe);
        ghost let stored=load8(to+i);
        proof {
            assert stored==copied;
            if i<observe {
                assert after_source==before_source;
                assert after_source==original;
            }
            if i>observe {
                assert after_dest==before_dest;
                assert after_dest==original;
            }
            if i==observe {
                copy_record_same_byte(to+i,to+observe);
                assert after_dest==stored;
                assert stored==before_source;
                assert before_source==original;
                assert after_dest==original;
            }
            assert (i>=observe) | (after_source==original);
            assert (i<observe) | (after_dest==original);
            copy_record_observation_step(i,observe,after_source,after_dest,original);
        }
        i=i+1;
    }
    return 0;
}

requires index>=0 && index<65536;
requires prior>=0 && prior<=index;
requires live==0 || live==1;
ensures prior+live>=prior;
ensures prior+live<=index+1;
lemma fn io_relocation_used_bound(index,prior,live) {
    if live==0 {
        assert prior+live==prior;
    }else {
        assert prior+live==prior+1;
        assert prior+1<=index+1;
    }
}

spec fn call_pc_byte(pc,observe) {return (pc>>((observe-16)*8))&255;}

requires byte>=0 && byte<8;
requires readable_bytes(word,8);
ensures readable_bytes(word+byte,1);
ensures load8(word+byte)==((load64(word)>>(byte*8))&255);
lemma fn call_record_word_byte(word,byte) {
    assert byte==0 || byte==1 || byte==2 || byte==3 || byte==4 || byte==5 || byte==6 || byte==7;
}

requires observe>=16 && observe<24;
requires stored==mapped+8;
requires observed==((stored>>((observe-16)*8))&255);
ensures observed==call_pc_byte(mapped+8,observe);
lemma fn call_record_observed_pc_byte(stored,mapped,observe,observed) {}

requires observe>=0 && observe<32 && (observe<16 || observe>=24);
requires writable_bytes(record,32);
ensures disjoint_bytes(record+16,8,record+observe,1);
lemma fn call_record_non_pc_byte_separate(record,observe) {
    assert observe<16 || observe>=24;
    assert record+observe>0;
}

requires call_count>=1 && call_count<=65536;
requires i>=0 && i<call_count;
requires calls_used>=0 && calls_used<=i;
requires pc>=0 && pc<=268435440 && (pc&15)==0;
requires writable_bytes(calls+i*32,32);
requires writable_bytes(calls+calls_used*32,32);
requires readable_bytes(calls+i*32+16,8);
requires load64(calls+i*32+16)==pc+8;
requires readable_bytes(io_flags+pc/16,1);
requires (load8(io_flags+pc/16)&1)==live;
requires live==0 || live==1;
requires readable_bytes(io_map+pc/2,8);
requires disjoint_bytes(calls+i*32+16,8,io_flags+pc/16,1);
requires disjoint_bytes(calls+calls_used*32,32,io_flags+pc/16,1);

requires observe>=0 && observe<32;
requires calls+calls_used*32<=calls+i*32;
requires calls_used==i || disjoint_bytes(calls+calls_used*32,32,calls+i*32,32);
requires load64(io_map+pc/2)==mapped_pc;

requires count>=1 && count<=16777216;
requires pc<=count*16-16;
requires readable_bytes(watched,8);
requires disjoint_bytes(calls+i*32+16,8,watched,8);
requires disjoint_bytes(calls+calls_used*32,32,watched,8);

modifies bytes(calls+i*32+16,8),bytes(calls+calls_used*32,32);
ensures load64(watched)==old(load64(watched));
ensures live==0 || result==old(calls_used)+1;
ensures live!=0 || result==old(calls_used);
ensures output_size==old(output_size);
ensures live!=0 ||
    load8(calls+old(calls_used)*32+observe)==old(load8(calls+calls_used*32+observe));
ensures live==0 || (observe>=16 && observe<24) ||
    load8(calls+old(calls_used)*32+observe)==old(load8(calls+i*32+observe));
ensures live==0 || observe<16 || observe>=24 ||
    load8(calls+old(calls_used)*32+observe)==call_pc_byte(mapped_pc+8,observe);
fn io_call_relocation_step(i,calls_used,pc,mapped_pc,observe,live,count,watched) {
    let size=count*16;
    ghost let initial_word=load64(watched);
    PRODUCTION_CALL_PC
    ghost let original_byte=load8(c+observe);
    ghost let destination=calls+calls_used*32;
    ghost let previous_byte=load8(destination+observe);
    proof {
        assert at==pc;
        assert live==0 || live==1;
    }
    PRODUCTION_CALL_BOUNDS
    PRODUCTION_LIVE_GUARD
        proof {
            assert live==1;
            if observe<16 || observe>=24 {call_record_non_pc_byte_separate(c,observe);}
            assert load64(io_map+at/2)==mapped_pc;
            assert disjoint_bytes(c+16,8,watched,8);
        }
        PRODUCTION_CALL_REWRITE
        ghost let observed_byte=load8(c+observe);
        proof {assert load64(watched)==initial_word;}
        proof {
            if observe<16 || observe>=24 {
                assert observed_byte==original_byte;
            }else {
                assert load64(c+16)==mapped_pc+8;
                assert c+observe==c+16+(observe-16);
                call_record_word_byte(c+16,observe-16);
                copy_record_same_byte(c+16+(observe-16),c+observe);
                call_record_observed_pc_byte(load64(c+16),mapped_pc,observe,observed_byte);
            }
        }
        proof {
            assert disjoint_bytes(c+16,8,watched,8);
            assert disjoint_bytes(calls+calls_used*32,32,watched,8);
        }
        PRODUCTION_RECORD_COPY
        proof {
            assert load8(calls+calls_used*32+observe)==observed_byte;
            assert load64(watched)==initial_word;
        }
        return calls_used+1;
    }
    proof {
        assert live==0;
        assert destination==calls+calls_used*32;
        assert load8(destination+observe)==previous_byte;
    }
    return calls_used;
}
