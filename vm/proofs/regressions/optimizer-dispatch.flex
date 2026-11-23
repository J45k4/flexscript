// Linked by the VM proof gate with the production compiler and interpreter.
fn emit_fixture(pc,opcode,operand) {
    store64(output+pc,opcode);
    store64(output+pc+8,operand);
    return pc+16;
}

fn prepare_dispatch_fixture(padding,arity,slots) {
    let pc=emit_fixture(0,18,0);
    let i=0;
    while i<padding {
        pc=emit_fixture(pc,1,123+i);
        i=i+1;
    }
    i=0;
    while i<arity {
        pc=emit_fixture(pc,1,321+i);
        pc=emit_fixture(pc,2,0);
        i=i+1;
    }
    pc=emit_fixture(pc,1,456);
    pc=emit_fixture(pc,8,1);
    pc=emit_fixture(pc,9,0);
    let callee=pc;
    pc=emit_fixture(pc,18,slots);
    pc=emit_fixture(pc,2,0x123456789abcdef0);
    pc=emit_fixture(pc,9,0x8000000000000007);
    output_size=pc;
    store64(functions+16,0);
    store64(functions+24,0);
    store64(functions+48,callee);
    store64(functions+56,arity);
    return callee;
}

fn check_dispatch_fixture(callee,arity,slots,instructions) {
    vm_steps=1;
    vm_fuel=instructions;
    vm_sp=0;
    vm_depth=0;
    vm_local_base=0;
    vm_local_top=0;
    vm_error=0;
    vm_finished=0;
    vm_acc=0;
    let i=0;
    while i<slots {store64(vm_local_memory+i*8,-111);i=i+1;}
    if vm_execute(0)!=456 || vm_error || !vm_finished || vm_depth!=0 || vm_pc!= -1 {return 5;}
    if vm_steps!=instructions+1 || vm_fuel!=0 || vm_sp!=0 || vm_local_base!=0 || vm_local_top!=0 {return 6;}
    if load64(vm_stack)!=456 {return 7;}
    i=0;
    while i<slots {
        let want=0;
        if i<arity {want=321+i;}
        if load64(vm_local_memory+i*8)!=want {return 7;}
        i=i+1;
    }
    if load64(vm_frames)!= -1 || load64(vm_frames+40)!=callee-16 || load64(vm_frames+64)!=0 {return 8;}
    return 0;
}

fn main() {
    output=alloc(1024);
    functions=alloc(64);
    if output<0 || functions<0 {return 1;}
    function_count=2;
    vm_allocate_core_buffers();
    if vm_frames<0 || vm_stack<0 || vm_local_memory<0 {return 4;}
    vm_restricted=1;
    vm_jit_enabled=0;
    let padding=1;
    while padding<=9 {
        let arity=0;
        while arity<=3 {
            let slots=arity+2;
            let callee=prepare_dispatch_fixture(padding,arity,slots);
            let original_size=output_size;
            let instructions=5+2*arity;
            ir_optimize();
            callee=callee-padding*16;
            if output_size!=original_size-padding*16 || load64(functions+48)!=callee || load64(functions+56)!=arity {return 2;}
            if load64(output+callee)!=18 || load64(output+callee+8)!=slots {return 3;}
            if load64(output+callee+16)!=2 || load64(output+callee+24)!=0x123456789abcdef0 {return 3;}
            if load64(output+callee+32)!=9 || load64(output+callee+40)!=0x8000000000000007 {return 3;}
            let status=check_dispatch_fixture(callee,arity,slots,instructions);
            if status {return status;}
            callee=prepare_dispatch_fixture(padding,arity,slots);
            status=check_dispatch_fixture(callee,arity,slots,instructions+padding);
            if status {return status;}
            arity=arity+1;
        }
        padding=padding+1;
    }
    return 0;
}
