// Normal execution of the fuel handler's MOV instructions, LEAVE and RET.
// The return word is the next RIP. The saved host continuation is supplied.
global x86_fuel_return_rax=0;
global x86_fuel_return_r11=0;
global x86_fuel_return_rbp=0;
global x86_fuel_return_rsp=0;

requires at>=0 && at<=0x7fffffffffffffff-22;
requires rbp>=32776 && rbp<=0x7fffffffffffffff-16;
requires slot>=-32776 && slot<=-8;
requires readable_bytes(at,22);
requires readable_bytes(rbp+slot,8);
requires load64(rbp+slot)==context;
requires readable_bytes(rbp,16);
requires writable_bytes(context+16,8);
requires disjoint_bytes(context+16,8,rbp,16);
requires disjoint_bytes(context+16,8,rbp+slot,8);
requires disjoint_bytes(context+16,8,at,22);
requires load8(at+0)==76;
requires load8(at+1)==139;
requires load8(at+2)==157;
requires load8(at+7)==73;
requires load8(at+8)==199;
requires load8(at+9)==67;
requires load8(at+10)==16;
requires load8(at+11)==1;
requires load8(at+12)==0;
requires load8(at+13)==0;
requires load8(at+14)==0;
requires load8(at+15)==184;
requires load8(at+16)==0;
requires load8(at+17)==0;
requires load8(at+18)==0;
requires load8(at+19)==0;
requires load8(at+20)==201;
requires load8(at+21)==195;
requires load8(at+3)==((slot>>0)&255);
requires load8(at+4)==((slot>>8)&255);
requires load8(at+5)==((slot>>16)&255);
requires load8(at+6)==((slot>>24)&255);
modifies x86_fuel_return_rax,x86_fuel_return_r11,x86_fuel_return_rbp,x86_fuel_return_rsp,bytes(context+16,8);
ensures result==old(load64(rbp+8));
ensures x86_fuel_return_rbp==old(load64(rbp));
ensures x86_fuel_return_rsp==rbp+16;
ensures x86_fuel_return_rax==0 && x86_fuel_return_r11==context;
ensures load64(context+16)==1;
ensures load64(rbp+slot)==context;
fn x86_fuel_return(at,rbp,slot,context) {
    let displacement=load8(at+3)|(load8(at+4)<<8)|(load8(at+5)<<16)|(load8(at+6)<<24);
    let decoded_slot=(displacement<<32)>>32;
    proof {assert decoded_slot==slot;}
    let decoded_context=load64(rbp+decoded_slot);
    proof {assert decoded_context==context;}
    x86_fuel_return_r11=decoded_context;
    let error_offset=(load8(at+10)<<56)>>56;
    let narrow=load8(at+11)|(load8(at+12)<<8)|(load8(at+13)<<16)|(load8(at+14)<<24);
    let error_word=(narrow<<32)>>32;
    proof {assert error_offset==16;assert error_word==1;}
    store64(decoded_context+error_offset,error_word);
    x86_fuel_return_rax=load8(at+16)|(load8(at+17)<<8)|(load8(at+18)<<16)|(load8(at+19)<<24);
    x86_fuel_return_rbp=load64(rbp);
    x86_fuel_return_rsp=rbp+16;
    return load64(rbp+8);
}
