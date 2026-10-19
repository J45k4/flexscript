import "cpu-cxx-builtins.flex";
// Validated word IR -> optimizing C++17 CPU kernel source.
// Word semantics and registered operations stay independent of application code.
global cpu_cxx_target=0;
fn cc_kind(index) {
    let f=functions+index*32;let kind=lowering_lookup(load64(f),load64(f+8),0);
    if kind && kind!=127 {return kind;}if kind==127 {return 0;}kind=gpu_intrinsic(index);if kind>=83 && kind<=90 && kind!=87 {return kind;}return 0;
}
fn cc_arity(op,arg) {if op==8 {return load64(functions+arg*32+24);}if arg>=1 && arg<=2 {return 1;}if arg>=3 && arg<=4 {return 2;}fail("CPU kernels cannot allocate, perform host I/O, or call FFI");return 0;}
fn cc_visit(index,level) {
    if cc_kind(index) {return 0;}if level>128 {fail("CPU kernel call depth exceeds 128");}
    if load64(p_seen+index*8)==1 {fail("recursive CPU kernels are unsupported");}
    if load64(p_seen+index*8)==2 {return 0;}store64(p_seen+index*8,1);
    let pc=load64(functions+index*32+16)+16;let end=p_end(index);
    while pc<end {let op=load64(p_code+pc);let arg=load64(p_code+pc+8);
        if op==8 {cc_visit(arg,level+1);}else if op==17 {cc_arity(op,arg);}
        else if op!=1 && op!=2 && op!=3 && op!=4 && op!=7 && op!=9 && op!=10 && op!=11 && op!=12 && op!=13 && op!=14 && op!=15 && op!=16 {fail("unsupported CPU kernel instruction");}pc=pc+16;
    }store64(p_seen+index*8,2);return 0;
}
fn cc_signature(index) {
    p_text("static CC_INLINE W flex_fn");p_num(index);p_text("(");let i=0;let count=load64(functions+index*32+24);
    if !count {p_text("void");}while i<count {if i {p_text(",");}p_text("W a");p_num(i);i=i+1;}p_text(")");return 0;
}
fn cc_intrinsic(kind,first,count) {
    hp_reg(p_acc);p_text("=");
    if kind==102 {p_text("1;\n");return 0;}
    if kind==100 || kind==101 {hp_reg(first);if kind==100 {p_text("+");}else {p_text("^");}hp_reg(first+1);p_text(";\n");return 0;}
    if kind>=83 && kind<=90 && kind!=87 {
        if kind==83 || kind==88 {p_text("__atomic_load_n((uint64_t*)(uintptr_t)");hp_reg(first);if kind==83 {p_text(",__ATOMIC_ACQUIRE)");}else {p_text(",__ATOMIC_RELAXED)");}}
        else if kind==84 {p_text("(__atomic_store_n((uint64_t*)(uintptr_t)");hp_reg(first);p_text(",");hp_reg(first+1);p_text(",__ATOMIC_RELEASE),");hp_reg(first+1);p_text(")");}
        else if kind==85 {p_text("__atomic_fetch_add((uint64_t*)(uintptr_t)");hp_reg(first);p_text(",");hp_reg(first+1);p_text(",__ATOMIC_ACQ_REL)");}
        else {p_text("(__atomic_thread_fence(__ATOMIC_SEQ_CST),0)");}p_text(";\n");return 0;
    }
    p_text("cc_op");p_num(kind);p_text("(");let i=0;while i<count {if i {p_text(",");}hp_reg(first+i);i=i+1;}p_text(");\n");return 0;
}
fn cc_function(index) {
    let f=functions+index*32;let start=load64(f+16)+16;let end=p_end(index);
    let slots=load64(p_code+start-8);let arity=load64(f+24);let maximum=0;
    p_depth=0;let pc=start;
    while pc<end {
        let op=load64(p_code+pc);let arg=load64(p_code+pc+8);
        if op==2 {p_depth=p_depth+1;if p_depth>maximum {maximum=p_depth;}}
        else if op==7 {p_depth=p_depth-1;}else if op==8 || op==17 {p_depth=p_depth-cc_arity(op,arg);}
        if p_depth<0 {fail("invalid CPU expression stack");}pc=pc+16;
    }
    if p_depth {fail("unbalanced CPU expression stack");}
    p_acc=slots;cc_signature(index);p_text(" {\n");let i=0;
    while i<slots+maximum+1 {p_text("W ");hp_reg(i);p_text("=");if i<arity {p_text("a");p_num(i);}else {p_text("0");}p_text(";\n");i=i+1;}
    pc=start;p_depth=0;
    while pc<end {
        let op=load64(p_code+pc);let arg=load64(p_code+pc+8);p_text("L");p_num(pc);p_text(":;\n");
        if op==1 {hp_reg(p_acc);p_text("=");p_hex(arg);p_text("ULL;\n");}
        else if op==2 {hp_move(slots+1+p_depth,p_acc);p_depth=p_depth+1;}
        else if op==3 {hp_move(p_acc,arg);}else if op==4 {hp_move(arg,p_acc);}
        else if op==7 {p_depth=p_depth-1;
            if arg==265 || arg==266 {hp_reg(p_acc);p_text("=cc_sh");if arg==265 {p_text("l");}else {p_text("r");}p_text("(");hp_reg(slots+1+p_depth);p_text(",");hp_reg(p_acc);p_text(");\n");}
            else {hp_binary(arg,slots+1+p_depth);}
        }
        else if op==8 {
            let n=cc_arity(op,arg);p_depth=p_depth-n;let first=slots+1+p_depth;
            if cc_kind(arg) {cc_intrinsic(cc_kind(arg),first,n);}
            else {hp_reg(p_acc);p_text("=flex_fn");p_num(arg);p_text("(");i=0;
                while i<n {if i {p_text(",");}hp_reg(first+i);i=i+1;}p_text(");\n");}
        }else if op==17 {
            p_depth=p_depth-cc_arity(op,arg);let first=slots+1+p_depth;hp_reg(p_acc);p_text("=");
            if arg==1 {p_text("*(unsigned char*)(uintptr_t)");hp_reg(first);}
            else if arg==2 {p_text("hp_unaligned_load(");hp_reg(first);p_text(")");}
            else if arg==3 {p_text("(*(unsigned char*)(uintptr_t)");hp_reg(first);p_text("=(unsigned char)");hp_reg(first+1);p_text(",");hp_reg(first+1);p_text(")");}
            else {p_text("hp_unaligned_store(");hp_reg(first);p_text(",");hp_reg(first+1);p_text(")");}p_text(";\n");
        }else if op==9 {p_text("return ");hp_reg(p_acc);p_text(";\n");}
        else if op==10 || op==11 || op==12 {
            if op!=10 {p_text("if(");if op==11 {p_text("!");}hp_reg(p_acc);p_text(") ");}p_text("goto L");p_num(arg);p_text(";\n");
        }else if op==13 || op==14 || op==15 || op==16 {
            hp_reg(p_acc);p_text("=");if op==13 {p_text("!!");}else if op==14 {p_text("0-");}
            else if op==15 {p_text("!");}else {p_text("~");}hp_reg(p_acc);p_text(";\n");
        }
        pc=pc+16;
    }
    p_text("}\n");return 0;
}
fn cpu_cxx_finish() {
    if global_count || vm_heap_used>16 {fail("CPU kernels do not support globals or static data");}
    let kernel=find(functions,function_count,"kernel",6);if kernel<0 || load64(functions+kernel*32+24)>6 {fail("CPU target requires kernel with at most six word parameters");}
    vm_mode=0;p_code=output;p_size=output_size;p_seen=alloc(function_count*8);if p_seen<0 {fail("cannot allocate CPU call graph");}cc_visit(kernel,0);
    output=alloc(output_limit);output_size=0;if output<0 {fail("cannot allocate CPU kernel output");}cc_builtins();let i=0;
    while i<function_count {if load64(p_seen+i*8) {cc_signature(i);p_text(";\n");}i=i+1;}
    i=0;while i<function_count {if load64(p_seen+i*8) {cc_function(i);}i=i+1;}
    p_text("extern \"C\" __attribute__((visibility(\"default\"))) uint64_t flex_kernel(");let arity=load64(functions+kernel*32+24);i=0;if !arity {p_text("void");}
    while i<arity {if i {p_text(",");}p_text("uint64_t a");p_num(i);i=i+1;}p_text("){unsigned csr=_mm_getcsr();_mm_setcsr(0x1f80);uint64_t result=flex_fn");p_num(kernel);p_text("(");i=0;while i<arity {if i {p_text(",");}p_text("a");p_num(i);i=i+1;}p_text(");_mm_setcsr(csr);return result;}\nextern \"C\" uint64_t flex_kernel_abi(void){return 1;}\nextern \"C\" uint64_t flex_kernel_arity(void){return ");p_num(arity);p_text(";}\n");return 0;
}
