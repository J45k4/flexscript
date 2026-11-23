fn fuel_exit_bytes(at,slot) {
    if load8(at)!=76 || load8(at+1)!=139 || load8(at+2)!=157 ||
       load8(at+7)!=73 || load8(at+8)!=199 || load8(at+9)!=67 || load8(at+10)!=16 ||
       load8(at+11)!=1 || load8(at+12)!=0 || load8(at+13)!=0 || load8(at+14)!=0 ||
       load8(at+15)!=184 || load8(at+16)!=0 || load8(at+17)!=0 ||
       load8(at+18)!=0 || load8(at+19)!=0 || load8(at+20)!=201 || load8(at+21)!=195 {return 0;}
    let i=0;
    while i<4 {
        if load8(at+3+i)!=((slot>>(i*8))&255) {return 0;}
        i=i+1;
    }
    return 1;
}

fn check_writeback(start,handler,rbp,slot,fuel) {
    store64(vm_jit_context+8,0);store64(vm_jit_context+16,77);
    vm_acc=99;vm_error=0;vm_fuel=fuel;vm_steps=0x7fffffffffffffff-fuel;vm_jit_calls=7;
    vm_frames=0;vm_depth=3;vm_pc=128;vm_local_base=16;vm_local_top=64;vm_sp=24;vm_finished=0;
    let saved_rbp=load64(rbp);
    let resume=load64(rbp+8);
    if x86_relocate_and_exhaust_fuel(start,rbp,slot,fuel,0,handler)!=1 ||
       vm_error!=1 || vm_acc!=0 || vm_fuel!=0 || vm_steps!=0x7fffffffffffffff || vm_jit_calls!=8 {return 0;}
    return x86_fuel_return_rax==0 && x86_fuel_return_r11==vm_jit_context &&
        x86_fuel_return_rbp==saved_rbp && x86_fuel_return_rsp==rbp+16 && x86_fuel_path_rip==resume &&
        load64(rbp)==saved_rbp && load64(rbp+8)==resume && load64(rbp+slot)==vm_jit_context &&
        load64(vm_jit_context+8)==0 && load64(vm_jit_context+16)==1 &&
        vm_depth==3 && vm_pc==128 && vm_local_base==16 && vm_local_top==64 && vm_sp==24 && vm_finished==0;
}

fn check_fuel_path(rbp,slots) {
    let start=1+(slots*139)%256;
    let slot=-8*(slots+1);
    output_size=start;vm_jit_context_slot=slot;vm_jit_error_count=0;
    vm_jit_meter();
    if output_size!=start+23 || vm_jit_error_count!=1 {return 2;}
    let handler=output_size+1+(slots%113);
    output_size=handler;
    store8(output+handler-1,71);store8(output+handler+22,72);
    if vm_jit_emit_fuel_exit()!=handler || output_size!=handler+22 ||
       !fuel_exit_bytes(output+handler,slot) || load8(output+handler-1)!=71 || load8(output+handler+22)!=72 {return 2;}
    store64(rbp+slot,vm_jit_context);store64(rbp,8192+slots);store64(rbp+8,65536+slots*8);
    if !check_writeback(start,handler,rbp,slot,0) ||
       !check_writeback(start,handler,rbp,slot,slots+1) {return 3;}
    return 0;
}

fn main() {
    output=alloc(512);vm_jit_errors=alloc(16);vm_jit_context=alloc(24);
    let stack=alloc(32792);
    if output<=0 || vm_jit_errors<=0 || vm_jit_context<=0 || stack<=0 {return 1;}
    let slots=0;
    while slots<=4096 {
        let status=check_fuel_path(stack+32776,slots);
        if status {return status;}
        slots=slots+1;
    }
    return 0;
}
