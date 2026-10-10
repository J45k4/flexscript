// Experimental direct word-IR -> NVIDIA PTX backend. No CUDA C or LLVM.
// Only the acyclic call graph rooted at kernel(index,input,output,count) is emitted.
global ptx_target=0;
global p_code=0;
global p_size=0;
global p_seen=0;
global p_acc=0;
global p_depth=0;
global p_advanced=0;

fn p_text(text) {let i=0;while load8(text+i) {emit(load8(text+i));i=i+1;}return 0;}
fn p_num(n) {
    if n>=10 {p_num(n/10);}emit(48+n%10);return 0;
}
fn p_hex(n) {
    p_text("0x");let i=60;
    while i>=0 {emit(load8("0123456789abcdef"+((n>>i)&15)));i=i-4;}return 0;
}
fn p_reg(n) {p_text("%v");p_num(n);return 0;}
fn p_move(to,from) {p_text("mov.b64 ");p_reg(to);p_text(", ");p_reg(from);p_text(";\n");return 0;}
fn p_end(index) {if index+1<function_count {return load64(functions+(index+1)*32+16);}return p_size;}
fn p_arity(op,arg) {
    if op==8 {return load64(functions+arg*32+24);}
    if op==17 && (arg==1 || arg==2) {return 1;}
    if op==17 && (arg==3 || arg==4) {return 2;}
    fail("PTX kernels cannot allocate, perform host I/O, or call FFI");return 0;
}
fn p_visit(index,level) {
    let intrinsic=gpu_intrinsic(index);if intrinsic {
        if load64(functions+index*32+24)!=gpu_intrinsic_arity(intrinsic) {fail("wrong GPU intrinsic arity");}
        p_advanced=1;return 0;
    }
    if level>128 {fail("PTX helper call depth exceeds 128");}
    let state=load64(p_seen+index*8);
    if state==1 {fail("PTX kernels cannot recurse");}if state==2 {return 0;}
    store64(p_seen+index*8,1);
    let pc=load64(functions+index*32+16)+16;let end=p_end(index);
    while pc<end {
        let op=load64(p_code+pc);let arg=load64(p_code+pc+8);
        if op==8 {p_visit(arg,level+1);}
        else if op==17 {p_arity(op,arg);}
        else if op!=1 && op!=2 && op!=3 && op!=4 && op!=7 && op!=9
            && op!=10 && op!=11 && op!=12 && op!=13 && op!=14 && op!=15 && op!=16 {
            fail("unsupported instruction in PTX kernel");
        }
        pc=pc+16;
    }
    store64(p_seen+index*8,2);return 0;
}
fn p_signature(index) {
    p_text(".func (.param .b64 result) flex_fn");p_num(index);p_text("(");
    let i=0;let arity=load64(functions+index*32+24);
    while i<arity {if i {p_text(", ");}p_text(".param .b64 a");p_num(i);i=i+1;}
    p_text(")");return 0;
}
fn p_bool(condition) {
    p_text("setp.");p_text(condition);p_text(".s64 %p, ");p_reg(p_acc);p_text(", 0;\nselp.u64 ");p_reg(p_acc);p_text(", 1, 0, %p;\n");return 0;
}
fn p_binary(op,left) {
    let instruction=0;
    if op==43 {instruction="add.u64";}else if op==45 {instruction="sub.u64";}
    else if op==42 {instruction="mul.lo.u64";}else if op==38 {instruction="and.b64";}
    else if op==124 {instruction="or.b64";}else if op==94 {instruction="xor.b64";}
    else if op==47 || op==37 {
        // PTX division is undefined at these inputs; preserve Flexscript traps.
        p_text("setp.eq.s64 %p, ");p_reg(p_acc);p_text(", 0;\n@%p trap;\nsetp.eq.s64 %p, ");
        p_reg(left);p_text(", 0x8000000000000000;\nsetp.eq.s64 %q, ");p_reg(p_acc);
        p_text(", -1;\nand.pred %p, %p, %q;\n@%p trap;\n");
        instruction="div.s64";if op==37 {instruction="rem.s64";}
    }else if op==265 || op==266 {
        p_text("and.b64 %t, ");p_reg(p_acc);p_text(", 63;\ncvt.u32.u64 %s, %t;\n");
        if op==265 {p_text("shl.b64 ");}else {p_text("shr.s64 ");}
        p_reg(p_acc);p_text(", ");p_reg(left);p_text(", %s;\n");return 0;
    }else {
        let condition=0;
        if op==259 {condition="eq";}else if op==260 {condition="ne";}
        else if op==60 {condition="lt";}else if op==62 {condition="gt";}
        else if op==261 {condition="le";}else if op==262 {condition="ge";}
        else {fail("invalid PTX binary operator");}
        p_text("setp.");p_text(condition);p_text(".s64 %p, ");p_reg(left);p_text(", ");p_reg(p_acc);
        p_text(";\nselp.u64 ");p_reg(p_acc);p_text(", 1, 0, %p;\n");return 0;
    }
    p_text(instruction);p_text(" ");p_reg(p_acc);p_text(", ");p_reg(left);p_text(", ");p_reg(p_acc);p_text(";\n");return 0;
}
fn p_memory(kind,first) {
    // Byte decomposition retains the language's unaligned little-endian accesses.
    let count=1;if kind==2 || kind==4 {count=8;}
    if kind<=2 {p_text("mov.u64 ");p_reg(p_acc);p_text(", 0;\n");}
    let i=0;
    while i<count {
        if kind<=2 {
            p_text("ld.global.u8 %b, [");p_reg(first);p_text("+");p_num(i);p_text("];\ncvt.u64.u32 %t, %b;\n");
            if i {p_text("shl.b64 %t, %t, ");p_num(i*8);p_text(";\n");}
            p_text("or.b64 ");p_reg(p_acc);p_text(", ");p_reg(p_acc);p_text(", %t;\n");
        }else {
            p_text("shr.u64 %t, ");p_reg(first+1);p_text(", ");p_num(i*8);
            p_text(";\ncvt.u32.u64 %b, %t;\nst.global.u8 [");p_reg(first);p_text("+");p_num(i);p_text("], %b;\n");
        }
        i=i+1;
    }
    if kind>=3 {p_move(p_acc,first+1);}return 0;
}
fn p_function(index) {
    let f=functions+index*32;let start=load64(f+16)+16;let end=p_end(index);
    let slots=load64(p_code+start-8);let arity=load64(f+24);let maximum=0;let call_max=0;
    p_depth=0;let pc=start;
    while pc<end {
        let op=load64(p_code+pc);let arg=load64(p_code+pc+8);
        if op==2 {p_depth=p_depth+1;if p_depth>maximum {maximum=p_depth;}}
        else if op==7 {p_depth=p_depth-1;}
        else if op==8 || op==17 {let n=p_arity(op,arg);p_depth=p_depth-n;if op==8 && n>call_max {call_max=n;}}
        if p_depth<0 {fail("invalid PTX expression stack");}pc=pc+16;
    }
    if p_depth {fail("unbalanced PTX expression stack");}
    p_acc=slots;p_signature(index);p_text(" {\n.reg .b64 %v<");p_num(slots+maximum+1);
    p_text(">;\n.reg .b64 %t;\n.reg .u32 %s, %b;\n.reg .b32 %r<16>;\n.reg .f32 %f<8>;\n.reg .f64 %d<4>;\n.reg .pred %p, %q;\n.param .b64 cr;\n");
    let i=0;while i<call_max {p_text(".param .b64 c");p_num(i);p_text(";\n");i=i+1;}
    i=0;while i<slots {
        if i<arity {p_text("ld.param.u64 ");p_reg(i);p_text(", [a");p_num(i);p_text("];\n");}
        else {p_text("mov.u64 ");p_reg(i);p_text(", 0;\n");}i=i+1;
    }
    pc=start;p_depth=0;
    while pc<end {
        let op=load64(p_code+pc);let arg=load64(p_code+pc+8);
        p_text("L");p_num(pc);p_text(":\n");
        if op==1 {p_text("mov.u64 ");p_reg(p_acc);p_text(", ");p_hex(arg);p_text(";\n");}
        else if op==2 {p_move(slots+1+p_depth,p_acc);p_depth=p_depth+1;}
        else if op==3 {p_move(p_acc,arg);}else if op==4 {p_move(arg,p_acc);}
        else if op==7 {p_depth=p_depth-1;p_binary(arg,slots+1+p_depth);}
        else if op==8 && gpu_intrinsic(arg) {
            let n=p_arity(op,arg);p_depth=p_depth-n;p_intrinsic(gpu_intrinsic(arg),slots+1+p_depth);
        }else if op==8 {
            let n=p_arity(op,arg);p_depth=p_depth-n;i=0;
            while i<n {p_text("st.param.b64 [c");p_num(i);p_text("], ");p_reg(slots+1+p_depth+i);p_text(";\n");i=i+1;}
            p_text("call.uni (cr), flex_fn");p_num(arg);p_text(", (");
            i=0;while i<n {if i {p_text(", ");}p_text("c");p_num(i);i=i+1;}
            p_text(");\nld.param.u64 ");p_reg(p_acc);p_text(", [cr];\n");
        }else if op==17 {p_depth=p_depth-p_arity(op,arg);p_memory(arg,slots+1+p_depth);}
        else if op==9 {p_text("st.param.b64 [result], ");p_reg(p_acc);p_text(";\nret;\n");}
        else if op==10 || op==11 || op==12 {
            if op!=10 {p_text("setp.");if op==11 {p_text("eq");}else {p_text("ne");}
                p_text(".s64 %p, ");p_reg(p_acc);p_text(", 0;\n@%p ");}
            p_text("bra L");p_num(arg);p_text(";\n");
        }else if op==13 {p_bool("ne");}else if op==15 {p_bool("eq");}
        else if op==14 || op==16 {
            if op==14 {p_text("neg.s64 ");}else {p_text("not.b64 ");}
            p_reg(p_acc);p_text(", ");p_reg(p_acc);p_text(";\n");
        }
        pc=pc+16;
    }
    p_text("}\n\n");return 0;
}
fn ptx_finish() {
    if global_count || vm_heap_used>16 {fail("PTX target does not support globals or static data");}
    let kernel=find(functions,function_count,"kernel",6);
    if kernel<0 {fail("PTX target requires kernel(index,input,output,count)");}
    if load64(functions+kernel*32+24)!=4 {fail("PTX kernel must take four parameters: index,input,output,count");}
    p_code=output;p_size=output_size;p_seen=alloc(function_count*8);
    if p_seen<0 {fail("cannot allocate PTX call graph");}p_visit(kernel,0);
    output=alloc(output_limit);output_size=0;if output<0 {fail("cannot allocate PTX output");}
    p_text("// Flexscript experimental PTX backend\n");
    if p_advanced {p_text(".version 6.5\n.target sm_75\n");}else {p_text(".version 6.0\n.target sm_50\n");}
    p_text(".address_size 64\n\n");
    if p_advanced {p_text(".extern .shared .align 8 .b8 flex_shared[];\n");}
    let i=0;while i<function_count {if load64(p_seen+i*8) {p_signature(i);p_text(";\n");}i=i+1;}
    i=0;while i<function_count {if load64(p_seen+i*8) {p_function(i);}i=i+1;}
    p_text(".visible .entry flex_kernel(.param .u64 input, .param .u64 output, .param .u64 count) {\n");
    p_text(".reg .u32 %block, %width, %thread, %tmp;\n.reg .u64 %index, %offset, %linear, %volume, %in, %out, %count;\n.reg .pred %outside;\n");
    p_text(".param .b64 a0, a1, a2, a3, result;\nmov.u32 %block, %ctaid.x;\nmov.u32 %width, %ntid.x;\nmov.u32 %thread, %tid.x;\n");
    p_text("mov.u32 %tmp, %ctaid.z;\ncvt.u64.u32 %linear, %tmp;\nmov.u32 %tmp, %nctaid.y;\ncvt.u64.u32 %offset, %tmp;\nmul.lo.u64 %linear, %linear, %offset;\nmov.u32 %tmp, %ctaid.y;\ncvt.u64.u32 %offset, %tmp;\nadd.u64 %linear, %linear, %offset;\nmov.u32 %tmp, %nctaid.x;\ncvt.u64.u32 %offset, %tmp;\nmul.lo.u64 %linear, %linear, %offset;\ncvt.u64.u32 %offset, %block;\nadd.u64 %linear, %linear, %offset;\n");
    p_text("mov.u32 %tmp, %ntid.y;\ncvt.u64.u32 %volume, %tmp;\nmov.u32 %tmp, %ntid.z;\ncvt.u64.u32 %offset, %tmp;\nmul.lo.u64 %volume, %volume, %offset;\ncvt.u64.u32 %offset, %width;\nmul.lo.u64 %volume, %volume, %offset;\nmul.lo.u64 %linear, %linear, %volume;\n");
    p_text("mov.u32 %tmp, %tid.z;\ncvt.u64.u32 %index, %tmp;\nmov.u32 %tmp, %ntid.y;\ncvt.u64.u32 %offset, %tmp;\nmul.lo.u64 %index, %index, %offset;\nmov.u32 %tmp, %tid.y;\ncvt.u64.u32 %offset, %tmp;\nadd.u64 %index, %index, %offset;\ncvt.u64.u32 %offset, %width;\nmul.lo.u64 %index, %index, %offset;\ncvt.u64.u32 %offset, %thread;\nadd.u64 %index, %index, %offset;\nadd.u64 %index, %index, %linear;\n");
    p_text("ld.param.u64 %count, [count];\nsetp.ge.u64 %outside, %index, %count;\n@%outside ret;\n");
    p_text("ld.param.u64 %in, [input];\nld.param.u64 %out, [output];\nst.param.b64 [a0], %index;\nst.param.b64 [a1], %in;\nst.param.b64 [a2], %out;\nst.param.b64 [a3], %count;\n");
    p_text("call.uni (result), flex_fn");p_num(kernel);p_text(", (a0, a1, a2, a3);\nret;\n}\n");return 0;
}
