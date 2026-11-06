// Inline acyclic word-IR helpers before PTX optimization. Each active call frame
// has distinct virtual locals; sibling calls reuse the same child frame.
global pi_frames=0;
global pi_instance=0;
fn pi_frame(index) {
    let record=pi_frames+index*24;if load64(record+16) {return load64(record+16);}
    let start=load64(functions+index*32+16)+16;let end=p_end(index);let slots=load64(p_code+start-8);let depth=0;let maximum=0;let child=0;let pc=start;
    while pc<end {let op=load64(p_code+pc);let arg=load64(p_code+pc+8);
        if op==2 {depth=depth+1;if depth>maximum {maximum=depth;}}
        else if op==7 {depth=depth-1;}
        else if op==8 || op==17 {depth=depth-p_arity(op,arg);if op==8 && !gpu_intrinsic(arg) {let n=pi_frame(arg);if n>child {child=n;}}}
        if depth<0 {fail("invalid inlined PTX expression stack");}pc=pc+16;
    }
    if depth {fail("unbalanced inlined PTX expression stack");}store64(record,slots);store64(record+8,maximum);store64(record+16,slots+maximum+1+child);return slots+maximum+1+child;
}
fn pi_label(instance,pc) {p_text("I");p_num(instance);p_text("_");p_num(pc);return 0;}
fn pi_function(index,base,result) {
    pi_instance=pi_instance+1;let instance=pi_instance;let start=load64(functions+index*32+16)+16;let end=p_end(index);
    let slots=load64(pi_frames+index*24);let maximum=load64(pi_frames+index*24+8);let acc=base+slots;let child=base+slots+maximum+1;let depth=0;
    let i=load64(functions+index*32+24);while i<slots {p_text("mov.u64 ");p_reg(base+i);p_text(",0;\n");i=i+1;}
    let pc=start;while pc<end {p_acc=acc;pi_label(instance,pc);p_text(":\n");let op=load64(p_code+pc);let arg=load64(p_code+pc+8);
        if op==1 {p_text("mov.u64 ");p_reg(acc);p_text(",");p_hex(arg);p_text(";\n");}
        else if op==2 {p_move(base+slots+1+depth,acc);depth=depth+1;}
        else if op==3 {p_move(acc,base+arg);}else if op==4 {p_move(base+arg,acc);}
        else if op==7 {depth=depth-1;p_binary(arg,base+slots+1+depth);}
        else if op==8 || op==17 {
            let arity=p_arity(op,arg);depth=depth-arity;let first=base+slots+1+depth;
            if op==17 {p_memory(arg,first);}else if gpu_intrinsic(arg) {p_intrinsic(gpu_intrinsic(arg),first);}
            else {i=0;while i<arity {p_move(child+i,first+i);i=i+1;}pi_function(arg,child,acc);}
        }else if op==9 {if result>=0 {p_move(result,acc);}p_text("bra ");pi_label(instance,end);p_text(";\n");}
        else if op==10 || op==11 || op==12 {
            if op!=10 {p_text("setp.");if op==11 {p_text("eq");}else {p_text("ne");}p_text(".s64 %p,");p_reg(acc);p_text(",0;\n@%p ");}
            p_text("bra ");pi_label(instance,arg);p_text(";\n");
        }else if op==13 {p_bool("ne");}else if op==15 {p_bool("eq");}
        else if op==14 || op==16 {if op==14 {p_text("neg.s64 ");}else {p_text("not.b64 ");}p_reg(acc);p_text(",");p_reg(acc);p_text(";\n");}
        pc=pc+16;
    }pi_label(instance,end);p_text(":\n");return 0;
}
fn pi_body(kernel) {
    pi_frames=alloc(function_count*24);pi_instance=0;let frame=pi_frame(kernel);
    p_text(".reg .b64 %v<");p_num(frame);p_text(">;\n.reg .b64 %t;\n.reg .u32 %s,%b;\n.reg .b32 %r<16>;\n.reg .f32 %f<8>;\n.reg .b16 %h<2>;\n.reg .f64 %d<4>;\n.reg .pred %p,%q;\n");
    p_text("mov.u64 %v0,%index;\nmov.u64 %v1,%in;\nmov.u64 %v2,%out;\nmov.u64 %v3,%count;\n");
    pi_function(kernel,0,-1);return 0;
}
