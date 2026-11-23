import "frame-state.flex";
import "../compiler/program-state.flex";
import "call-locals.flex";

// An instruction consists of two words. Check the size before subtraction.
fn vm_instruction_outside(pc,size) {
    return size<16 || pc<0 || pc>size-16 || (pc&15)!=0;
}

fn vm_call_capacity(count,slots) {
    if count<0 || slots<count || slots>4096 || vm_sp<count*8
        || vm_local_top+slots*8>8388608 {vm_error=9;return 0;}
    // Caller operands below its saved floor are not arguments to this call.
    // The preceding checks also bound count before multiplying/subtracting it.
    if vm_depth {
        let floor=load64(vm_frames+(vm_depth-1)*40+24);
        if floor<0 || floor>vm_sp || count*8>vm_sp-floor {vm_error=9;return 0;}
    }
    return 1;
}

fn vm_enter(index,return_pc) {
    if index<0 || index>=function_count || vm_depth>=1024 {vm_error=4;return 0;}
    let entry=functions+index*32;let pc=load64(entry+16);
    if vm_instruction_outside(pc,output_size) {vm_error=9;return 0;}
    if load64(output+pc)!=18 {vm_error=9;return 0;}
    let count=load64(entry+24);let slots=load64(output+pc+8);
    let available=vm_call_capacity(count,slots);
    if !available {return 0;}
    return vm_enter_accepted(index,return_pc,pc,count,slots);
}

fn vm_install_call_frame(index,return_pc,count,slots) {
    let frame=vm_frames+vm_depth*40;
    store64(frame,return_pc);store64(frame+8,vm_local_base);store64(frame+16,vm_local_top);
    store64(frame+24,vm_sp-count*8);store64(frame+32,index);
    vm_local_base=vm_local_top;vm_local_top=vm_local_top+slots*8;
    return 0;
}

// The call guards have checked the instruction and operand/local capacity.
fn vm_enter_accepted(index,return_pc,pc,count,slots) {
    vm_install_call_frame(index,return_pc,count,slots);
    vm_copy_call_locals(vm_stack+(vm_sp-count*8),vm_local_memory+vm_local_base,count,slots);
    vm_sp=vm_sp-count*8;vm_depth=vm_depth+1;vm_pc=pc+16;return 1;
}
