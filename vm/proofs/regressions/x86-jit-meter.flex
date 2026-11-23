fn check_meter_fuel(at,saved,context,slot,delta,fuel) {
    store64(context+8,fuel);
    x86_meter_r11=0;
    let next=x86_meter_step(at,saved-slot,slot,context,delta);
    let expected=at+23;
    if fuel==0 {expected=at+18+delta;}
    return next==expected && x86_meter_r11==context &&
        load64(context+8)==fuel-(fuel>0) && load64(context+16)==77 && load64(saved)==context;
}

fn check_meter_layout(start,slot,row,saved,context,delta) {
    output_size=start;vm_jit_context_slot=slot;vm_jit_error_count=row;
    store8(output+start-1,101);store8(output+start+23,102);
    if vm_jit_meter()!=0 || output_size!=start+23 || vm_jit_error_count!=row+1 {return 2;}
    let at=output+start;
    if load8(at+0)!=76 || load8(at+1)!=139 || load8(at+2)!=157 ||
       load8(at+7)!=73 || load8(at+8)!=131 || load8(at+9)!=123 || load8(at+10)!=8 || load8(at+11)!=0 ||
       load8(at+12)!=15 || load8(at+13)!=132 ||
       load8(at+18)!=73 || load8(at+19)!=131 || load8(at+20)!=107 || load8(at+21)!=8 || load8(at+22)!=1 {return 3;}
    let byte=0;
    while byte<4 {
        if load8(at+3+byte)!=((slot>>(byte*8))&255) || load8(at+14+byte)!=0 {return 3;}
        byte=byte+1;
    }
    if load8(at-1)!=101 || load8(at+23)!=102 {return 3;}
    let record=vm_jit_errors+row*16;
    if load64(record)!=start+14 || load64(record+8)!=1 {return 4;}
    let target=start+18+delta;
    if vm_jit_patch_fuel_record(row,row,start+14,target+16,target,target+32,target+48,target+64)!=row+1 {return 4;}
    if load64(record)!=start+14 || load64(record+8)!=1 ||
       load8(at+12)!=15 || load8(at+13)!=132 || load8(at+18)!=73 {return 4;}
    if !check_meter_fuel(at,saved,context,slot,delta,0) ||
       !check_meter_fuel(at,saved,context,slot,delta,1) ||
       !check_meter_fuel(at,saved,context,slot,delta,7) ||
       !check_meter_fuel(at,saved,context,slot,delta,0x7fffffffffffffff) {return 5;}
    return 0;
}

fn main() {
    output=alloc(288);vm_jit_errors=alloc(524288);
    let saved=alloc(8);let context=alloc(24);
    if output<=0 || vm_jit_errors<=0 || saved<=0 || context<=0 {return 1;}
    store64(saved,context);store64(context+16,77);
    let slots=0;
    while slots<=4096 {
        let delta=6+slots*16383;
        let status=check_meter_layout(1+(slots*139)%256,-8*(slots+1),(slots*83)&32767,saved,context,delta);
        if status {return status;}
        slots=slots+1;
    }
    return 0;
}
