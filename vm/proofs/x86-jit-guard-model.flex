// Branch destinations for the relocated native division guard.

requires delta>=0 && delta<=67108864;
requires readable_bytes(address,4);
requires load8(address)==(delta&255);
requires load8(address+1)==((delta>>8)&255);
requires load8(address+2)==((delta>>16)&255);
requires load8(address+3)==((delta>>24)&255);
modifies nothing;
ensures result==delta;
fn x86_decode_forward_rel32(address,delta) {
    let b0=load8(address);
    let b1=load8(address+1);
    let b2=load8(address+2);
    let b3=load8(address+3);
    proof {x86_forward_rel32_bytes(delta,b0,b1,b2,b3);}
    return b0|(b1<<8)|(b2<<16)|(b3<<24);
}

requires entry>=0 && entry<=67108864-39;
requires division>=entry+39 && division<=67108864;
requires zero_delta>=0 && zero_delta<=67108864;
requires overflow_delta>=0 && overflow_delta<=67108864;
requires entry+9+zero_delta==division;
requires entry+39+overflow_delta==division;
requires readable_bytes(code+entry,39);
requires right==0 || readable_bytes(stack,8);
requires right==0 || load64(stack)==left;
requires load8(code+entry+0)==72;
requires load8(code+entry+1)==133;
requires load8(code+entry+2)==192;
requires load8(code+entry+3)==15;
requires load8(code+entry+4)==132;
requires load8(code+entry+9)==72;
requires load8(code+entry+10)==185;
requires load8(code+entry+11)==0;
requires load8(code+entry+12)==0;
requires load8(code+entry+13)==0;
requires load8(code+entry+14)==0;
requires load8(code+entry+15)==0;
requires load8(code+entry+16)==0;
requires load8(code+entry+17)==0;
requires load8(code+entry+18)==128;
requires load8(code+entry+19)==72;
requires load8(code+entry+20)==57;
requires load8(code+entry+21)==12;
requires load8(code+entry+22)==36;
requires load8(code+entry+23)==15;
requires load8(code+entry+24)==133;
requires load8(code+entry+25)==10;
requires load8(code+entry+26)==0;
requires load8(code+entry+27)==0;
requires load8(code+entry+28)==0;
requires load8(code+entry+29)==72;
requires load8(code+entry+30)==131;
requires load8(code+entry+31)==248;
requires load8(code+entry+32)==255;
requires load8(code+entry+33)==15;
requires load8(code+entry+34)==132;
requires load8(code+entry+5)==((zero_delta>>0)&255);
requires load8(code+entry+6)==((zero_delta>>8)&255);
requires load8(code+entry+7)==((zero_delta>>16)&255);
requires load8(code+entry+8)==((zero_delta>>24)&255);
requires load8(code+entry+35)==((overflow_delta>>0)&255);
requires load8(code+entry+36)==((overflow_delta>>8)&255);
requires load8(code+entry+37)==((overflow_delta>>16)&255);
requires load8(code+entry+38)==((overflow_delta>>24)&255);
modifies nothing;
ensures result==division || result==entry+39;
ensures !(right==0 || left==0x8000000000000000 && right==(-1)) || result==division;
ensures right==0 || left==0x8000000000000000 && right==(-1) || result==entry+39;
fn x86_model_division_guard_destination(code,entry,stack,left,right,division,zero_delta,overflow_delta) {
    proof {
        x86_guard_decoding_spans(code+entry);
    }
    if (right&right)==0 {
        let delta=x86_decode_forward_rel32(code+entry+5,zero_delta);
        return entry+9+delta;
    }
    let left_word=load64(stack);
    if left_word-load64(code+entry+11)!=0 {
        let delta=x86_decode_forward_rel32(code+entry+25,10);
        return entry+29+delta;
    }
    let narrow=load8(code+entry+32);
    let immediate=(narrow<<56)>>56;
    if right-immediate==0 {
        let delta=x86_decode_forward_rel32(code+entry+35,overflow_delta);
        return entry+39+delta;
    }
    return entry+39;
}

requires value>=0 && value<=67108864;
requires b0==(value&255);
requires b1==((value>>8)&255);
requires b2==((value>>16)&255);
requires b3==((value>>24)&255);
ensures (b3&128)==0;
ensures (b0|(b1<<8)|(b2<<16)|(b3<<24))==value;
lemma fn x86_forward_rel32_bytes(value,b0,b1,b2,b3) {
    assert (value&0xffffffff)==value;
}

requires readable_bytes(address,39);
ensures readable_bytes(address+5,4);
ensures readable_bytes(address+25,4);
ensures readable_bytes(address+35,4);
lemma fn x86_guard_decoding_spans(address) {}
