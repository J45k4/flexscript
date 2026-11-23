fn seed_writeback(remaining,error,steps,calls) {
    store64(vm_jit_context,111);store64(vm_jit_context+8,remaining);
    store64(vm_jit_context+16,error);store64(vm_jit_context+24,444);
    vm_acc=55;vm_fuel=123;vm_error=4;vm_steps=steps;vm_jit_calls=calls;
    vm_pc=96;vm_local_base=40;vm_local_top=64;vm_sp=32;vm_finished=0;
}

fn writeback_totals(fuel,remaining,error,word,steps,calls) {
    return vm_acc==word && vm_fuel==remaining && vm_error==error &&
        vm_steps==steps+(fuel-remaining) && vm_jit_calls==calls+1 &&
        load64(vm_jit_context)==111 && load64(vm_jit_context+8)==remaining &&
        load64(vm_jit_context+16)==error && load64(vm_jit_context+24)==444;
}

fn check_success(frames,depth,return_pc,finished,fuel,remaining) {
    let steps=0x7fffffffffffffff-fuel;let calls=0x7ffffffffffffffe;
    seed_writeback(remaining,0,steps,calls);
    vm_frames=frames;vm_depth=depth;vm_finished=finished;
    let top=frames+(depth-1)*40;
    store64(top,return_pc);store64(top+8,8);store64(top+16,24);store64(top+24,16);store64(top+32,777);
    let word=0x8000000000000000;
    if vm_jit_writeback(fuel,word)!=1 || !writeback_totals(fuel,remaining,0,word,steps,calls) {return 2;}
    if return_pc==-1 {finished=1;}
    if vm_depth!=depth-1 || vm_pc!=return_pc || vm_local_base!=8 || vm_local_top!=24 ||
       vm_sp!=16 || vm_finished!=finished || load64(top+32)!=777 {return 3;}
    return 0;
}

fn check_trap(frames,depth,error,fuel,remaining) {
    seed_writeback(remaining,error,19,7);
    vm_frames=frames;vm_depth=depth;
    let word=-8421;
    if vm_jit_writeback(fuel,word)!=1 {return 2;}
    if vm_error!=error || vm_depth!=depth || vm_pc!=96 || vm_local_base!=40 ||
       vm_local_top!=64 || vm_sp!=32 || vm_finished {return 3;}
    if !writeback_totals(fuel,remaining,error,word,19,7) {return 2;}
    return 0;
}

fn main() {
    let frames=alloc(40960);vm_jit_context=alloc(32);
    if frames<=0 || vm_jit_context<=0 {return 1;}
    let status=check_success(frames,1,-1,0,7,3);
    if status {return status;}
    status=check_success(frames,1024,80,1,7,7);
    if status {return status;}
    status=check_success(frames,1024,-1,1,7,0);
    if status {return status;}
    status=check_success(frames,1,80,0,1,0);
    if status {return status;}
    status=check_trap(0,0,2,7,3);
    if status {return status;}
    status=check_trap(frames,1024,1,0,0);
    if status {return status;}
    status=check_trap(frames,1,3,7,7);
    if status {return status;}
    status=check_trap(frames,1024,8,7,0);
    if status {return status;}
    status=check_trap(frames,1,9,7,6);
    if status {return status;}
    return check_trap(0,0,-1,7,2);
}
