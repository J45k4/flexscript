// Project the architecturally relevant state of MOV, CMP, JE and SUB.
// On a normal x86-64 machine step, the meter exposes its R11 and next RIP.
global x86_meter_r11=0;

requires slot>=-32776 && slot<=-8;
requires displacement>=6 && displacement<=67108864;
requires at>=0 && at<=0x7fffffffffffffff-67108882;
requires readable_bytes(at,23);
requires readable_bytes(rbp+slot,8);
requires load64(rbp+slot)==context;
requires writable_bytes(context+8,8);
requires load64(context+8)>=0;
requires disjoint_bytes(context+8,8,at,23);
requires disjoint_bytes(context+8,8,rbp+slot,8);
requires load8(at+0)==76;
requires load8(at+1)==139;
requires load8(at+2)==157;
requires load8(at+7)==73;
requires load8(at+8)==131;
requires load8(at+9)==123;
requires load8(at+10)==8;
requires load8(at+11)==0;
requires load8(at+12)==15;
requires load8(at+13)==132;
requires load8(at+18)==73;
requires load8(at+19)==131;
requires load8(at+20)==107;
requires load8(at+21)==8;
requires load8(at+22)==1;
requires load8(at+3)==((slot>>0)&255);
requires load8(at+4)==((slot>>8)&255);
requires load8(at+5)==((slot>>16)&255);
requires load8(at+6)==((slot>>24)&255);
requires load8(at+14)==((displacement>>0)&255);
requires load8(at+15)==((displacement>>8)&255);
requires load8(at+16)==((displacement>>16)&255);
requires load8(at+17)==((displacement>>24)&255);
modifies x86_meter_r11,bytes(context+8,8);
ensures x86_meter_r11==context;
ensures load64(rbp+slot)==context;
ensures old(load64(context+8))!=0 || result==at+18+displacement;
ensures old(load64(context+8))<=0 || result!=at+18+displacement;
ensures result!=at+18+displacement || load64(context+8)==0;
ensures old(load64(context+8))<=0 || result==at+23;
ensures old(load64(context+8))<=0 || load64(context+8)==old(load64(context+8))-1;
ensures load64(context+8)>=0;
fn x86_meter_step(at,rbp,slot,context,displacement) {
    let encoded_slot=load8(at+3)|(load8(at+4)<<8)|(load8(at+5)<<16)|(load8(at+6)<<24);
    let context_slot=(encoded_slot<<32)>>32;
    proof {
        assert context_slot==slot;
        assert rbp+context_slot==rbp+slot;
    }
    let decoded_context=load64(rbp+context_slot);
    proof {assert decoded_context==context;}
    x86_meter_r11=decoded_context;
    let cmp_offset=(load8(at+10)<<56)>>56;
    let limit=(load8(at+11)<<56)>>56;
    proof {assert cmp_offset==8;assert limit==0;}
    let fuel=load64(decoded_context+cmp_offset);
    if fuel-limit==0 {
        let delta=load8(at+14)|(load8(at+15)<<8)|(load8(at+16)<<16)|(load8(at+17)<<24);
        let signed_delta=(delta<<32)>>32;
        proof {assert delta==displacement;assert signed_delta==displacement;}
        return at+18+signed_delta;
    }
    let write_offset=(load8(at+21)<<56)>>56;
    let decrement=(load8(at+22)<<56)>>56;
    proof {assert write_offset==8;assert decrement==1;assert fuel>0;}
    store64(decoded_context+write_offset,fuel-decrement);
    proof {assert load64(context+8)==fuel-1;assert load64(rbp+slot)==context;}
    return at+23;
}
