fn guard_case(stack,left,right,start,division) {
    store64(stack,left);
    let expected=start+39;
    if right==0 || left==0x8000000000000000 && right==(-1) {expected=division;}
    let destination=x86_model_division_guard_destination(output,start,stack,left,right,division,
        division-start-9,division-start-39);
    if destination!=expected || load64(stack)!=left {return 5;}
    return 0;
}

fn check_guard(stack,start,first,division) {
    output_size=start;
    vm_jit_error_count=first;
    store8(output+start-1,107);
    store8(output+start+39,173);
    if vm_jit_division_guard(start,first)!=0 || output_size!=start+39 || vm_jit_error_count!=first+2 {return 2;}
    if load8(output+start-1)!=107 || load8(output+start+39)!=173 {return 2;}
    if load8(output+start+0)!=72 {return 3;}
    if load8(output+start+1)!=133 {return 3;}
    if load8(output+start+2)!=192 {return 3;}
    if load8(output+start+3)!=15 {return 3;}
    if load8(output+start+4)!=132 {return 3;}
    if load8(output+start+5)!=0 {return 3;}
    if load8(output+start+6)!=0 {return 3;}
    if load8(output+start+7)!=0 {return 3;}
    if load8(output+start+8)!=0 {return 3;}
    if load8(output+start+9)!=72 {return 3;}
    if load8(output+start+10)!=185 {return 3;}
    if load8(output+start+11)!=0 {return 3;}
    if load8(output+start+12)!=0 {return 3;}
    if load8(output+start+13)!=0 {return 3;}
    if load8(output+start+14)!=0 {return 3;}
    if load8(output+start+15)!=0 {return 3;}
    if load8(output+start+16)!=0 {return 3;}
    if load8(output+start+17)!=0 {return 3;}
    if load8(output+start+18)!=128 {return 3;}
    if load8(output+start+19)!=72 {return 3;}
    if load8(output+start+20)!=57 {return 3;}
    if load8(output+start+21)!=12 {return 3;}
    if load8(output+start+22)!=36 {return 3;}
    if load8(output+start+23)!=15 {return 3;}
    if load8(output+start+24)!=133 {return 3;}
    if load8(output+start+25)!=10 {return 3;}
    if load8(output+start+26)!=0 {return 3;}
    if load8(output+start+27)!=0 {return 3;}
    if load8(output+start+28)!=0 {return 3;}
    if load8(output+start+29)!=72 {return 3;}
    if load8(output+start+30)!=131 {return 3;}
    if load8(output+start+31)!=248 {return 3;}
    if load8(output+start+32)!=255 {return 3;}
    if load8(output+start+33)!=15 {return 3;}
    if load8(output+start+34)!=132 {return 3;}
    if load8(output+start+35)!=0 {return 3;}
    if load8(output+start+36)!=0 {return 3;}
    if load8(output+start+37)!=0 {return 3;}
    if load8(output+start+38)!=0 {return 3;}
    let record=vm_jit_errors+first*16;
    if load64(record)!=start+5 || load64(record+8)!=2 || load64(record+16)!=start+35 || load64(record+24)!=2 {return 4;}
    vm_jit_patch_division_record(first,first,start+5,1,2,division,3,8);
    vm_jit_patch_division_record(first+1,first+1,start+35,1,2,division,3,8);
    let iteration=0;
    let word=0x512e4602600b7d5c;
    while iteration<64 {
        word=word*6364136223846793005+1442695040888963407;
        let status=guard_case(stack,word,0,start,division);
        if status {return status;}
        status=guard_case(stack,word,(-1),start,division);
        if status {return status;}
        status=guard_case(stack,0x8000000000000000,word,start,division);
        if status {return status;}
        status=guard_case(stack,word,(word<<17)^(word>>41),start,division);
        if status {return status;}
        status=guard_case(stack,0x8000000000000000,(-1),start,division);
        if status {return status;}
        iteration=iteration+1;
    }
    return 0;
}

fn main() {
    output=alloc(67108864);
    vm_jit_errors=alloc(32768*16);
    let stack=alloc(8);
    if output<=0 || vm_jit_errors<=0 || stack<=0 {return 1;}
    let stripe=0;
    while stripe<32 {
        let start=stripe*173+1;
        let status=check_guard(stack,start,stripe*1055,start+39+stripe*313);
        if status {return status;}
        status=check_guard(stack,67108864-300+stripe,32766,67108864-1);
        if status {return status;}
        stripe=stripe+1;
    }
    return 0;
}
