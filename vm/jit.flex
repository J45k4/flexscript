// Baseline x86-64 JIT for verified compiler-owned leaf bytecode.
// Native code preserves the VM's fuel and deadline checks. Pages are RW while
// copying, then RX for execution. Guest offsets never expose these pages.
global vm_jit_buffer=0;
global vm_jit_map=0;
global vm_jit_branches=0;
global vm_jit_branch_count=0;
global vm_jit_errors=0;
global vm_jit_error_count=0;
global vm_jit_context_slot=0;
global vm_jit_bytes=0;
fn vm_jit_load_context() {
    emit(76);emit(139);emit(157);emit32(vm_jit_context_slot);return 0;
}
fn vm_jit_error_jump(op,kind) {
    let at=jump(op);let record=vm_jit_errors+vm_jit_error_count*16;
    store64(record,at);store64(record+8,kind);vm_jit_error_count=vm_jit_error_count+1;return at;
}
fn vm_jit_meter() {
    vm_jit_load_context();
    emit(73);emit(131);emit(123);emit(8);emit(0); // cmp [r11+8],0
    vm_jit_error_jump(132,1);
    emit(73);emit(131);emit(107);emit(8);emit(1); // sub [r11+8],1
    return 0;
}
fn vm_jit_clock() {
    vm_jit_load_context();
    emit(73);emit(131);emit(67);emit(24);emit(1); // increment backedge count
    emit(73);emit(247);emit(67);emit(24);emit32(1023);
    let skip=jump(133);
    emit(80);emit(81);emit(82);emit(87);emit(86);
    emit(73);emit(141);emit(115);emit(40); // timespec at context+40
    emit(191);emit32(1);emit(184);emit32(228);emit(15);emit(5);
    emit(133);emit(192);vm_jit_error_jump(136,8);
    vm_jit_load_context();
    emit(73);emit(139);emit(67);emit(40);
    emit(72);emit(105);emit(192);emit32(1000);emit(80);
    emit(73);emit(139);emit(67);emit(48);emit(49);emit(210);
    emit(191);emit32(1000000);emit(72);emit(247);emit(247);
    emit(89);emit(72);emit(1);emit(200);
    emit(73);emit(59);emit(67);emit(32);vm_jit_error_jump(141,8);
    emit(94);emit(95);emit(90);emit(89);emit(88);patch_jump(skip);return 0;
}
fn vm_jit_local(slot,storing) {
    emit(72);if storing {emit(137);}else {emit(139);}
    emit(133);emit32(-8*(slot+1));return 0;
}
fn vm_jit_division_guard() {
    test_rax();vm_jit_error_jump(132,2);
    emit(72);emit(185);emit64(-9223372036854775807-1);
    emit(72);emit(57);emit(12);emit(36); // cmp [rsp],rcx
    let safe=jump(133);
    emit(72);emit(131);emit(248);emit(255);vm_jit_error_jump(132,2);
    patch_jump(safe);return 0;
}
fn vm_jit_compile(index) {
    let bytecode=output;let bytecode_size=output_size;
    let start=load64(functions+index*32+16);let end=bytecode_size;
    if index+1<function_count {end=load64(functions+(index+1)*32+16);}
    if start<0 || end<=start || end>bytecode_size || (end-start)%16 || (end-start)/16>8192 {return 0;}
    let slots=load64(bytecode+start+8);let pc=start+16;
    if load64(bytecode+start)!=18 || slots<0 || slots>4096 {return 0;}
    while pc<end {
        let op=load64(bytecode+pc);let arg=load64(bytecode+pc+8);
        // Calls, allocation, guest pointer accesses, FFI and host I/O stay in
        // the checked interpreter. No speculative assumptions or deoptimization.
        if op<1 || (op>16 && op!=21 && op!=22) || op==8 {return 0;}
        if (op==3 || op==4) && (arg<0 || arg>=slots) {return 0;}
        if (op==5 || op==6) && vm_restricted && (arg<16 || arg>vm_heap_used-8) {return 0;}
        if (op==21 || op==22) && ((arg>>32)<1 || (arg&4294967295)<16 || (arg>>32)>(vm_heap_used-(arg&4294967295))/8) {return 0;}
        if (op==10 || op==11 || op==12) && (arg<start+16 || arg>=end || arg%16) {return 0;}
        if op==7 && !precedence(arg) {return 0;}
        pc=pc+16;
    }
    if !vm_jit_buffer {
        vm_jit_buffer=alloc(67108864);vm_jit_map=alloc(8193*8);
        vm_jit_branches=alloc(8192*16);vm_jit_errors=alloc(8192*64);
        if vm_jit_buffer<0 || vm_jit_map<0 || vm_jit_branches<0 || vm_jit_errors<0 {
            vm_jit_cleanup();vm_jit_buffer=0;vm_jit_map=0;vm_jit_branches=0;vm_jit_errors=0;
            vm_jit_enabled=0;return 0;
        }
    }
    output=vm_jit_buffer;output_size=0;vm_mode=0;
    vm_jit_branch_count=0;vm_jit_error_count=0;vm_jit_context_slot=-8*(slots+1);
    emit(85);emit(72);emit(137);emit(229);
    emit(72);emit(129);emit(236);emit32(((slots*8+8+15)/16)*16);
    emit(72);emit(137);emit(189);emit32(vm_jit_context_slot);
    emit(72);emit(139);emit(55); // context->local slots in rsi
    let i=0;while i<slots {
        emit(72);emit(139);emit(134);emit32(i*8);vm_jit_local(i,1);i=i+1;
    }
    pc=start+16;
    while pc<end {
        store64(vm_jit_map+((pc-start)/16)*8,output_size);vm_jit_meter();
        let op=load64(bytecode+pc);let arg=load64(bytecode+pc+8);
        if op==1 {immediate(arg);}
        else if op==2 {emit(80);}
        else if op==3 || op==4 {vm_jit_local(arg,op==4);}
        else if op==5 || op==6 {
            emit(72);emit(186);emit64(vm_address(arg,8));
            emit(72);if op==5 {emit(139);}else {emit(137);}emit(2);
        }else if op==21 || op==22 {
            if op==21 {emit(72);emit(137);emit(193);}else {emit(89);}
            emit(72);emit(129);emit(249);emit32(arg>>32);vm_jit_error_jump(131,3);
            emit(72);emit(186);emit64(vm_heap+(arg&4294967295));emit(72);if op==21 {emit(139);}else {emit(137);}emit(4);emit(202);
        }else if op==7 {if arg==47 || arg==37 {vm_jit_division_guard();}binary(arg);}
        else if op==9 {epilogue();}
        else if op==10 || op==11 || op==12 {
            if arg<=pc {vm_jit_clock();}
            let kind=233;if op==11 {kind=132;test_rax();}else if op==12 {kind=133;test_rax();}
            let at=jump(kind);let record=vm_jit_branches+vm_jit_branch_count*16;
            store64(record,at);store64(record+8,(arg-start)/16);vm_jit_branch_count=vm_jit_branch_count+1;
        }else if op==13 {normalize();}
        else if op==14 || op==16 {emit(72);emit(247);if op==14 {emit(216);}else {emit(208);}}
        else if op==15 {test_rax();emit(15);emit(148);emit(192);emit(72);emit(15);emit(182);emit(192);}
        pc=pc+16;
    }
    // Keep all failure exits outside guest control-flow targets.
    let failure=output_size;vm_jit_load_context();emit(73);emit(199);emit(67);emit(16);emit32(9);immediate(0);epilogue();
    let fuel=output_size;vm_jit_load_context();emit(73);emit(199);emit(67);emit(16);emit32(1);immediate(0);epilogue();
    let division=output_size;vm_jit_load_context();emit(73);emit(199);emit(67);emit(16);emit32(2);immediate(0);epilogue();
    let bounds=output_size;vm_jit_load_context();emit(73);emit(199);emit(67);emit(16);emit32(3);immediate(0);epilogue();
    let timeout=output_size;vm_jit_load_context();emit(73);emit(199);emit(67);emit(16);emit32(8);immediate(0);epilogue();
    i=0;while i<vm_jit_error_count {
        let record=vm_jit_errors+i*16;let at=load64(record);let kind=load64(record+8);let target=failure;
        if kind==1 {target=fuel;}else if kind==2 {target=division;}else if kind==8 {target=timeout;}else if kind==3 {target=bounds;}
        patch32(at,target-at-4);i=i+1;
    }
    i=0;while i<vm_jit_branch_count {
        let record=vm_jit_branches+i*16;let at=load64(record);let target=load64(vm_jit_map+load64(record+8)*8);
        patch32(at,target-at-4);i=i+1;
    }
    let bytes=((output_size+4095)/4096)*4096;let code=0;
    if bytes<=1048576 && bytes<=16777216-vm_jit_bytes {
        code=syscall(9,0,bytes,3,34,-1,0);
        if code>0 {
            i=0;while i<output_size {store8(code+i,load8(output+i));i=i+1;}
            if syscall(10,code,bytes,5,0,0,0)<0 {syscall(11,code,bytes,0,0,0,0);code=0;}
        }else {code=0;}
    }
    output=bytecode;output_size=bytecode_size;vm_mode=1;
    if code {
        let cache=vm_jit_cache+index*32;store64(cache,code);store64(cache+8,bytes);
        vm_jit_bytes=vm_jit_bytes+bytes;vm_jit_compilations=vm_jit_compilations+1;
    }
    return code;
}
fn vm_try_jit(index) {
    let cache=vm_jit_cache+index*32;if load64(cache+24)==2 {return 0;}
    let calls=load64(cache+16)+1;store64(cache+16,calls);let code=load64(cache);
    if !code && calls>=vm_jit_threshold {
        code=vm_jit_compile(index);if !code {store64(cache+24,2);return 0;}
    }
    if !code {return 0;}
    if vm_now()>=vm_deadline {vm_error=8;return 0;}
    store64(vm_jit_context,vm_local_memory+vm_local_base);store64(vm_jit_context+8,vm_fuel);
    store64(vm_jit_context+16,0);store64(vm_jit_context+24,0);store64(vm_jit_context+32,vm_deadline);
    let fuel=vm_fuel;vm_acc=ffi_call(code,vm_jit_context,0,0,0,0,0);
    vm_fuel=load64(vm_jit_context+8);vm_error=load64(vm_jit_context+16);
    vm_steps=vm_steps+fuel-vm_fuel;vm_jit_calls=vm_jit_calls+1;
    if !vm_error {vm_return();}return 1;
}
fn vm_jit_cleanup() {
    let i=0;while i<function_count {
        let cache=vm_jit_cache+i*32;let code=load64(cache);
        if code {syscall(11,code,load64(cache+8),0,0,0,0);}i=i+1;
    }
    if vm_jit_buffer>0 {syscall(11,vm_jit_buffer,67108864,0,0,0,0);}
    if vm_jit_map>0 {syscall(11,vm_jit_map,8193*8,0,0,0,0);}
    if vm_jit_branches>0 {syscall(11,vm_jit_branches,8192*16,0,0,0,0);}
    if vm_jit_errors>0 {syscall(11,vm_jit_errors,8192*64,0,0,0,0);}return 0;
}
