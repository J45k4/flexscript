// Explicit symbol-to-operation bindings. Portable bodies remain the fallback.
// Records: name, length, operation, target (0=all, 1=native x86-64, 2=GPU, 3=CPU C++).
global lowering_entries=0;
global lowering_count=0;
global lowering_reference=0;
fn lowering_operation(p,n) {
    if equal(p,n,"machine.call1",13) {return 127;}
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
    if equal(p,n,"memory.copy",11) {return 120;}
    if equal(p,n,"memory.fill",11) {return 121;}
    if equal(p,n,"word.store32",12) {return 125;}
    if equal(p,n,"word.load32",11) {return 122;}
    if equal(p,n,"word.high_bit",13) {return 123;}
    if equal(p,n,"memory.common_prefix",20) {return 124;}
    if equal(p,n,"word.add",8) {return 100;}
    if equal(p,n,"word.xor",8) {return 101;}
    if equal(p,n,"lowering.active",15) {return 102;}
    fail("unknown lowering operation");return 0;
}
fn lowering_arity(op) {if op==125 || op==127 {return 2;}if op>=120 && op<=124 {if op==122 || op==123 {return 1;}return 3;}if op==110 {return 6;}if op==102 {return 0;}if op==34 || op==44 {return 1;}return 2;}
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
    if op==127 {
        // Caller spills volatile locals before entering this operation. The
        // machine function follows System V, including preserving RBP.
        lowering_bytes("5f58554889e54883e4f0ffd04889ec5d");return 0;
    }
    if op>=120 && op<=125 {return lowering_memory(op);}
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

// Reusable exact-bound byte operations. SSE2/BSR and REP are baseline x86-64;
// no CPUID-dependent instructions or external runtime helpers are needed.
fn lowering_memory(op) {
    if op==125 {emit(88);emit(95);emit(137);emit(7);return 0;}
    if op==122 {emit(95);emit(139);emit(7);return 0;} // pop rdi; mov eax,[rdi]
    if op==123 {
        emit(88);emit(72);emit(15);emit(189);emit(192); // bsr rax,rax
        let nonzero=jump(133);immediate(-1);patch_jump(nonzero);return 0;
    }
    emit(89); // count -> rcx
    if op==120 {return lowering_copy();}
    if op==121 {
        emit(88);emit(95);emit(72);emit(137);emit(250); // byte/dst; rdx=dst
        emit(252);emit(243);emit(170);emit(72);emit(137);emit(208);return 0;
    }
    emit(95);emit(94);emit(49);emit(192); // b -> rdi, a -> rsi, offset -> rax
    let loop=output_size;
    emit(72);emit(131);emit(249);emit(16);let tail=jump(130);
    // Compare exactly sixteen bytes, returning the earliest differing byte.
    emit(243);emit(15);emit(111);emit(4);emit(6);
    emit(243);emit(15);emit(111);emit(12);emit(7);
    emit(102);emit(15);emit(116);emit(193);
    emit(102);emit(15);emit(215);emit(208);
    emit(129);emit(242);emit32(65535);let mismatch=jump(133);
    emit(72);emit(131);emit(192);emit(16);emit(72);emit(131);emit(233);emit(16);
    let back=jump(233);patch32(back,loop-back-4);
    patch_jump(tail);let bytes=output_size;
    emit(72);emit(133);emit(201);let empty=jump(132);
    emit(15);emit(182);emit(20);emit(6);emit(58);emit(20);emit(7);let different=jump(133);
    emit(72);emit(255);emit(192);emit(72);emit(255);emit(201);
    back=jump(233);patch32(back,bytes-back-4);
    patch_jump(mismatch);emit(15);emit(188);emit(210);emit(72);emit(1);emit(208);
    patch_jump(empty);patch_jump(different);return 0;
}

fn lowering_bytes(s) {let i=0;while load8(s+i) {let a=load8(s+i);let b=load8(s+i+1);let high=a&15;let low=b&15;if a>57 {high=high+9;}if b>57 {low=low+9;}emit((high<<4)|low);i=i+2;}return 0;}
// Exact small copies use SSE2 and scalar edge loads. All loads precede stores
// in the overlapping first/last short cases. Right-overlap retains forward REP
// semantics; large ranges use ERMS where the hardware implements it efficiently.
fn lowering_copy() {
    lowering_bytes("5e5f4889f84885c9");let empty=jump(132);
    lowering_bytes("4881f980000000");let large=jump(131);
    lowering_bytes("4839f7");let normal=jump(134);
    lowering_bytes("4889fa4829f24839ca");let alias=jump(130);
    patch_jump(normal);let loop=output_size;lowering_bytes("4883f920");let small=jump(134);
    lowering_bytes("f30f6f06f30f7f074883c6104883c7104883e910");let back=jump(233);patch32(back,loop-back-4);
    patch_jump(small);lowering_bytes("4883f910");let under16=jump(130);
    lowering_bytes("f30f6f06f30f6f4c0ef0f30f7f07f30f7f4c0ff0");let end16=jump(233);
    patch_jump(under16);lowering_bytes("4883f908");let under8=jump(130);
    lowering_bytes("f30f7e06488b540ef8660fd6074889540ff8");let end8=jump(233);
    patch_jump(under8);lowering_bytes("4883f904");let under4=jump(130);
    lowering_bytes("660f6e068b540efc660f7e0789540ffc");let end4=jump(233);
    patch_jump(under4);lowering_bytes("4883f902");let under2=jump(130);
    lowering_bytes("0fb7160fb7740efe6689176689740ffe");let end2=jump(233);
    patch_jump(under2);lowering_bytes("8a168817");let end1=jump(233);
    patch_jump(large);patch_jump(alias);lowering_bytes("fcf3a4");
    patch_jump(empty);patch_jump(end16);patch_jump(end8);patch_jump(end4);patch_jump(end2);patch_jump(end1);return 0;
}
