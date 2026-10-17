// Explicit symbol-to-operation bindings. Portable bodies remain the fallback.
// Records: name, length, operation, target (0=all, 1=native x86-64, 2=GPU, 3=CPU C++).
global lowering_entries=0;
global lowering_count=0;
global lowering_reference=0;
fn lowering_operation(p,n) {
    if equal(p,n,"f32x2.add",9){return 112;}if equal(p,n,"f32x2.sub",9){return 113;}if equal(p,n,"f32x2.mul",9){return 114;}
    if equal(p,n,"f32.add",7) {return 30;}
    if equal(p,n,"f32.sub",7) {return 31;}
    if equal(p,n,"f32.mul",7) {return 32;}
    if equal(p,n,"f32.div",7) {return 33;}
    if equal(p,n,"f32.sqrt",8) {return 34;}
    if equal(p,n,"f64.add",7) {return 40;}
    if equal(p,n,"f64.sub",7) {return 41;}
    if equal(p,n,"f64.mul",7) {return 42;}
    if equal(p,n,"f64.div",7) {return 43;}
    if equal(p,n,"f64.sqrt",8) {return 44;}
    if equal(p,n,"f32.dot3",8) {return 110;}
    if equal(p,n,"f32.dot3.load",13) {return 111;}
    if equal(p,n,"word.add",8) {return 100;}
    if equal(p,n,"word.xor",8) {return 101;}
    if equal(p,n,"lowering.active",15) {return 102;}
    fail("unknown lowering operation");return 0;
}
fn lowering_arity(op) {if op==110 {return 6;}if op==102 {return 0;}if op==34 || op==44 {return 1;}return 2;}
fn lowering_declaration() {
    next();if token!=256 {fail("expected lowering function name");}
    let name=source+token_start;let size=token_size;
    if reserved(name,size) {fail("reserved lowering function name");}
    next();if token!=258 {fail("expected quoted lowering operation");}
    let op=lowering_operation(source+token_start+1,token_size-2);next();let target=0;
    if token==258 {
        let p=source+token_start+1;let n=token_size-2;
        if equal(p,n,"native-x86_64",13) {target=1;}
        else if equal(p,n,"gpu",3) {target=2;}
        else if equal(p,n,"cpu-cxx",7) {target=3;}
        else {fail("unknown lowering target");}next();
    }
    expect(59);
    let i=0;while i<lowering_count {let r=lowering_entries+i*32;
        if equal(name,size,load64(r),load64(r+8)) && (target==0 || load64(r+24)==0 || target==load64(r+24) || (target==1 && load64(r+24)==3) || (target==3 && load64(r+24)==1)) {
            fail("duplicate or conflicting lowering registration");
        }i=i+1;
    }
    if lowering_count>=2048 {fail("too many lowering registrations");}
    let r=lowering_entries+lowering_count*32;lowering_count=lowering_count+1;
    store64(r,name);store64(r+8,size);store64(r+16,op);store64(r+24,target);return 0;
}
fn lowering_validate() {
    let i=0;while i<lowering_count {let r=lowering_entries+i*32;
        let index=find(functions,function_count,load64(r),load64(r+8));
        if index<0 {locate_name(load64(r));fail("lowering requires a defined function");}
        if load64(functions+index*32+24)!=lowering_arity(load64(r+16)) {
            locate_name(load64(r));fail("wrong lowering function arity");
        }i=i+1;
    }return 0;
}
fn lowering_lookup(name,size,gpu) {
    if !gpu && (vm_mode || baremetal_target || lowering_reference) {return 0;}
    let i=0;while i<lowering_count {let r=lowering_entries+i*32;let target=load64(r+24);
        if (target==0 || (gpu && target==2) || (!gpu && target==1) || (!gpu && target==3 && cpu_cxx_target)) && equal(name,size,load64(r),load64(r+8)) {
            let op=load64(r+16);if gpu && op>=100 {return 0;}if !cpu_cxx_target && op>=112 && op<=114 {return 0;}return op;
        }i=i+1;
    }return 0;
}
// Arguments are already evaluated once, left to right, on the word stack.
// SSE2 is baseline x86-64. No fast math, fusion, FTZ or DAZ.
fn lowering_native(op) {
    if op==102 {immediate(1);return 0;}
    if op==110 || op==111 {return lowering_dot3(op);}
    if lowering_arity(op)==2 {emit(89);}emit(88); // rhs -> rcx, lhs -> rax
    if op==100 || op==101 {emit(72);if op==100 {emit(1);}else {emit(49);}emit(200);return 0;}
    let wide=op>=40;
    emit(102);if wide {emit(72);}emit(15);emit(110);emit(192);
    if lowering_arity(op)==2 {emit(102);if wide {emit(72);}emit(15);emit(110);emit(201);}
    if wide {emit(242);}else {emit(243);}emit(15);
    let kind=op;if wide {kind=op-10;}
    if kind==30 {emit(88);}else if kind==31 {emit(92);}else if kind==32 {emit(89);}else if kind==33 {emit(94);}else {emit(81);}
    if kind==34 {emit(192);}else {emit(193);}
    return lowering_native_result(wide);
}
fn lowering_native_result(wide) {
    // Software word APIs canonicalize NaNs; hardware payload/sign is irrelevant.
    if wide {emit(102);}emit(15);emit(46);emit(192);let nan=jump(138);
    emit(102);if wide {emit(72);}emit(15);emit(126);emit(192);let done=jump(233);
    patch_jump(nan);if wide {immediate(0x7ff8000000000000);}else {immediate(0x7fc00000);}patch_jump(done);return 0;
}
fn lowering_entry(entry) {
    let op=lowering_lookup(load64(entry),load64(entry+8),0);if !op {return 0;}
    store64(entry+16,output_size);emit(85);emit(72);emit(137);emit(229);
    let i=0;let count=load64(entry+24);
    while i<count {emit(72);emit(139);emit(133);emit32(16+(count-i-1)*8);emit(80);i=i+1;}
    lowering_native(op);epilogue();return 0;
}

// Fixed vector primitives retain separate, ordered binary32 rounding. These
// are reusable numeric operations, independent of any physics data layout.
fn lowering_dot_load(reg,offset,base) {
    emit(102);emit(15);emit(110);
    emit(64|(reg<<3)|base);if base==4 {emit(36);}emit(offset);return 0;
}
fn lowering_dot3(op) {
    if op==111 {emit(89);emit(88);}
    let i=0;while i<3 {
        let left=0;let right=1;if i {left=1;right=2;}
        if op==110 {lowering_dot_load(left,(5-i)*8,4);lowering_dot_load(right,(2-i)*8,4);}
        else {lowering_dot_load(left,i*8,0);lowering_dot_load(right,i*8,1);}
        emit(243);emit(15);emit(89);emit(192|(left<<3)|right);
        if i {emit(243);emit(15);emit(88);emit(193);}i=i+1;
    }
    if op==110 {emit(72);emit(131);emit(196);emit(48);}
    return lowering_native_result(0);
}
