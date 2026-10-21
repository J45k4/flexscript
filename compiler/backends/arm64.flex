import "../../lib/arm64-code.flex";
// Direct word IR -> AArch64 Linux ELF. No assembler, linker or interpreter.
// AAPCS64 integer calls: x0-x7 arguments, x0 result, remaining arguments on
// a 16-byte-aligned stack. x29/x30 form the frame record; x18 is never used.
// Locals and expression temporaries live in the frame, across nested calls.
global arm64_target=0;
global a64_object=0;
global a64_data_base=0x10000000;
global a64_ir=0;
global a64_ir_size=0;
global a64_map=0;
global a64_fixups=0;
global a64_fixup_count=0;
global a64_slots=0;
global a64_depth=0;
global a64_relocations=0;
global a64_relocation_count=0;
global a64_entries=0;

fn a64_relocation(at,kind,addend) {
    if a64_relocation_count>=a64_ir_size/8 {fail("too many ARM64 object relocations");}
    let record=a64_relocations+a64_relocation_count*24;
    store64(record,at);store64(record+8,kind);store64(record+16,addend);
    a64_relocation_count=a64_relocation_count+1;return 0;
}
fn a64_static(reg,offset) {
    if !a64_object {return a64_const(reg,a64_data_base+offset);}
    a64_relocation(output_size,275,offset);a64_ins(0x90000000|reg);
    a64_relocation(output_size,277,offset);a64_ins(0x91000000|(reg<<5)|reg);
    return 0;
}

fn a64_ins(word) {emit32(word);return 0;}
fn a64_mov(dst,src) {return a64_ins(arm64_word_mov(dst,src));}
fn a64_const(reg,value) {
    a64_ins(arm64_word_movz(reg,value));
    let shift=16;
    while shift<64 {
        let part=(value>>shift)&65535;
        if part {a64_ins(arm64_word_movk(reg,part,shift));}
        shift=shift+16;
    }return 0;
}
fn a64_rr(op,dst,left,right) {return a64_ins(arm64_word_rr(op,dst,left,right));}
fn a64_cmp(left,right) {return a64_ins(arm64_word_cmp(left,right));}
fn a64_cset(dst,condition) {return a64_ins(arm64_word_cset(dst,condition));}
fn a64_mem(store,reg,base,offset) {
    if offset<0 || offset%8 || offset>32760 {fail("ARM64 memory offset out of range");}
    return a64_ins(arm64_word_mem(store,reg,base,offset));
}
fn a64_local(store,reg,slot) {
    a64_const(9,(slot+1)*8);a64_rr(0xcb000000,10,29,9);
    return a64_mem(store,reg,10,0);
}
fn a64_stack(bytes,release) {
    if !bytes {return 0;}
    a64_const(9,bytes);
    // ADD/SUB extended register accepts SP, unlike the shifted-register form.
    let op=0xcb2063ff;if release {op=0x8b2063ff;}
    return a64_ins(op|(9<<16));
}
fn a64_branch() {let at=output_size;a64_ins(0x14000000);return at;}
fn a64_patch_branch(at,to,link) {
    let delta=to-at;
    if delta%4 || delta< -134217728 || delta>=134217728 {fail("ARM64 branch out of range");}
    patch32(at,arm64_word_branch(delta,link));return 0;
}
fn a64_cond(condition) {let at=output_size;a64_ins(0x54000000|condition);return at;}
fn a64_patch_cond(at,to) {
    let delta=to-at;
    if delta%4 || delta< -1048576 || delta>=1048576 {fail("ARM64 conditional branch out of range");}
    patch32(at,arm64_word_cond(delta,load8(output+at)&15));return 0;
}
fn a64_guard(condition) {
    // Skip BRK if the condition holds. AArch64 SDIV itself does not trap.
    a64_ins(0x54000040|condition);a64_ins(0xd4200000);return 0;
}
fn a64_fix(target,link) {
    if a64_fixup_count>=a64_ir_size/16+1 {fail("too many ARM64 relocations");}
    let at=a64_branch();let entry=a64_fixups+a64_fixup_count*24;
    store64(entry,at);store64(entry+8,target);store64(entry+16,link);
    a64_fixup_count=a64_fixup_count+1;return 0;
}
fn a64_arity(op,arg) {
    if op==8 {return load64(functions+arg*32+24);}
    if op!=17 {return 0;}
    if arg==1 || arg==2 || arg==5 {return 1;}
    if arg==3 || arg==4 {return 2;}
    if arg==6 || arg==9 || arg==10 || arg==11 {return 7;}
    fail("ARM64 dynamic FFI is not supported");return 0;
}
fn a64_binary(op) {
    // Left operand x1, right operand x0; all values are signed 64-bit words.
    if op==43 {a64_rr(0x8b000000,0,1,0);}
    else if op==45 {a64_rr(0xcb000000,0,1,0);}
    else if op==42 {a64_rr(0x9b007c00,0,1,0);}
    else if op==47 || op==37 {
        a64_cmp(0,31);a64_guard(1);
        a64_const(9,-1);a64_cmp(0,9);let ordinary=a64_cond(1);
        a64_const(9,-9223372036854775807-1);a64_cmp(1,9);a64_guard(1);
        a64_patch_cond(ordinary,output_size);
        a64_rr(0x9ac00c00,9,1,0); // SDIV x9,x1,x0
        if op==37 {a64_ins(0x9b008000|(0<<16)|(1<<10)|(9<<5));} // MSUB x0,x9,x0,x1
        else {a64_mov(0,9);}
    }else if op==38 {a64_rr(0x8a000000,0,1,0);}
    else if op==124 {a64_rr(0xaa000000,0,1,0);}
    else if op==94 {a64_rr(0xca000000,0,1,0);}
    else if op==265 {a64_rr(0x9ac02000,0,1,0);}
    else if op==266 {a64_rr(0x9ac02800,0,1,0);}
    else {
        let condition=0;
        if op==259 {condition=0;}else if op==260 {condition=1;}
        else if op==60 {condition=11;}else if op==62 {condition=12;}
        else if op==261 {condition=13;}else if op==262 {condition=10;}
        else {fail("invalid ARM64 binary operator");}
        a64_cmp(1,0);a64_cset(0,condition);
    }return 0;
}
fn a64_builtin(kind,first) {
    let count=a64_arity(17,kind);let i=0;
    while i<count {a64_local(0,i,first+i);i=i+1;}
    if kind==1 {a64_ins(0x39400000);} // LDRB w0,[x0]
    else if kind==2 {a64_mem(0,0,0,0);}
    else if kind==3 || kind==4 {
        if kind==3 {a64_ins(0x39000001);}else {a64_mem(1,1,0,0);}
        a64_mov(0,1);
    }else if kind==5 {
        a64_cmp(0,31);let zero=a64_cond(0);let negative=a64_cond(11);
        a64_mov(1,0);a64_const(0,0);a64_const(2,3);a64_const(3,34);
        a64_const(4,-1);a64_const(5,0);a64_const(8,222);a64_ins(0xd4000001);
        let done=a64_branch();a64_patch_cond(zero,output_size);a64_const(0,-22);
        let zero_done=a64_branch();a64_patch_cond(negative,output_size);a64_const(0,-12);
        a64_patch_branch(done,output_size,0);a64_patch_branch(zero_done,output_size,0);
    }else if kind==6 {
        // Raw Linux ARM64 syscall(number,a,b,c,d,e,f), not x86 syscall IDs.
        a64_mov(8,0);i=0;while i<6 {a64_mov(i,i+1);i=i+1;}
        a64_ins(0xd4000001);
    }else if kind==9 || kind==10 || kind==11 {
        // AAPCS64 integer/pointer call through a trusted host-supplied address.
        // Dynamic library loading and symbol lookup remain host operations.
        a64_mov(9,0);i=0;while i<6 {a64_mov(i,i+1);i=i+1;}
        a64_ins(0xd63f0120); // BLR x9
        if kind==10 {a64_ins(0x93407c00);} // SXTW x0,w0
        else if kind==11 {a64_ins(0x2a0003e0);} // MOV w0,w0
    }return 0;
}
fn a64_word_io(reading) {
    // Match native FIR: complete eight-byte little-endian words, -1 on EOF/error.
    a64_stack(16,0);if reading {a64_const(0,0);}a64_mem(1,0,31,0);
    a64_ins(0x910003ed); // MOV x13,sp
    a64_const(14,8);let loop=output_size;
    let fd=1;let number=64;if reading {fd=0;number=63;}
    a64_const(0,fd);a64_mov(1,13);a64_mov(2,14);a64_const(8,number);a64_ins(0xd4000001);
    a64_const(9,-4);a64_cmp(0,9);let retry=a64_cond(0);a64_patch_cond(retry,loop);
    a64_cmp(0,31);let failed=a64_cond(13);
    a64_rr(0x8b000000,13,13,0);a64_rr(0xcb000000,14,14,0);
    a64_cmp(14,31);let more=a64_cond(1);a64_patch_cond(more,loop);
    a64_mem(0,0,31,0);let done=a64_branch();
    a64_patch_cond(failed,output_size);a64_const(0,-1);a64_patch_branch(done,output_size,0);
    a64_stack(16,1);return 0;
}
fn a64_return() {
    a64_ins(0x910003bf); // MOV sp,x29
    a64_ins(0xa8c17bfd); // LDP x29,x30,[sp],#16
    a64_ins(0xd65f03c0);return 0;
}
fn a64_call(index,first) {
    let count=load64(functions+index*32+24);let extra=0;
    if count>8 {extra=((count-8)*8+15)& -16;}
    a64_stack(extra,0);let i=0;
    while i<count {
        if i<8 {a64_local(0,i,first+i);}
        else {a64_local(0,11,first+i);a64_mem(1,11,31,(i-8)*8);}
        i=i+1;
    }
    a64_fix(load64(functions+index*32+16),1);a64_stack(extra,1);return 0;
}
fn a64_function(index) {
    let entry=functions+index*32;let start=load64(entry+16);let end=a64_ir_size;
    if index+1<function_count {end=load64(functions+(index+1)*32+16);}
    a64_slots=load64(a64_ir+start+8);let count=load64(entry+24);
    if load64(a64_ir+start)!=18 || a64_slots<count || a64_slots>4096 {fail("invalid ARM64 function frame");}
    let maximum=0;a64_depth=0;let pc=start+16;
    while pc<end {
        let op=load64(a64_ir+pc);let arg=load64(a64_ir+pc+8);
        if op==2 {a64_depth=a64_depth+1;if a64_depth>maximum {maximum=a64_depth;}}
        else if op==7 || op==22 {a64_depth=a64_depth-1;}
        else if op==8 || op==17 {a64_depth=a64_depth-a64_arity(op,arg);}
        if a64_depth<0 {fail("invalid ARM64 expression stack");}
        if (op==10 || op==11 || op==12) && (arg<start+16 || arg>=end || arg%16) {fail("invalid ARM64 branch target");}
        pc=pc+16;
    }
    if a64_depth {fail("unbalanced ARM64 expression stack");}
    store64(a64_map+start/2,output_size);
    if a64_object {store64(a64_entries+index*8,output_size);}
    a64_ins(0xa9bf7bfd);a64_ins(0x910003fd); // save FP/LR, MOV x29,sp
    a64_stack(((a64_slots+maximum)*8+15)& -16,0);
    let i=0;
    while i<a64_slots {
        if i<count {
            if i<8 {a64_local(1,i,i);}
            else {a64_mem(0,11,29,16+(i-8)*8);a64_local(1,11,i);}
        }else {a64_local(1,31,i);}
        i=i+1;
    }
    a64_depth=0;pc=start+16;
    while pc<end {
        store64(a64_map+pc/2,output_size);
        let op=load64(a64_ir+pc);let arg=load64(a64_ir+pc+8);
        if op==1 {a64_const(0,arg);}
        else if op==2 {a64_local(1,0,a64_slots+a64_depth);a64_depth=a64_depth+1;}
        else if op==3 || op==4 {a64_local(op==4,0,arg);}
        else if op==5 || op==6 {a64_static(10,arg);a64_mem(op==6,0,10,0);}
        else if op==23 && a64_object {a64_static(0,arg);}
        else if op==7 {a64_depth=a64_depth-1;a64_local(0,1,a64_slots+a64_depth);a64_binary(arg);}
        else if op==8 {a64_depth=a64_depth-a64_arity(op,arg);a64_call(arg,a64_slots+a64_depth);}
        else if op==9 {a64_return();}
        else if op==10 {a64_fix(arg,0);}
        else if op==11 || op==12 {
            a64_cmp(0,31);let condition=1;if op==12 {condition=0;}
            a64_ins(0x54000040|condition);a64_fix(arg,0);
        }else if op==13 || op==15 {a64_cmp(0,31);let condition=1;if op==15 {condition=0;}a64_cset(0,condition);}
        else if op==14 {a64_rr(0xcb000000,0,31,0);}
        else if op==16 {a64_ins(0xaa2003e0);}
        else if op==17 {a64_depth=a64_depth-a64_arity(op,arg);a64_builtin(arg,a64_slots+a64_depth);}
        else if op==19 || op==20 {a64_word_io(op==20);}
        else if op==21 || op==22 {
            if op==22 {a64_depth=a64_depth-1;a64_local(0,1,a64_slots+a64_depth);}else {a64_mov(1,0);}
            a64_const(9,arg>>32);a64_cmp(1,9);a64_guard(3); // unsigned LO
            a64_static(10,arg&4294967295);
            a64_ins(0x8b010c00|(10<<5)|10); // ADD x10,x10,x1,LSL #3
            a64_mem(op==22,0,10,0);
        }else {fail("unsupported ARM64 IR instruction");}
        pc=pc+16;
    }return 0;
}
fn a64_segment(at,kind,flags,offset,address,size,alignment) {
    patch32(at,kind);patch32(at+4,flags);store64(output+at+8,offset);
    store64(output+at+16,address);store64(output+at+24,address);
    store64(output+at+32,size);store64(output+at+40,size);store64(output+at+48,alignment);return 0;
}
fn a64_section(at,name,kind,flags,address,offset,size,alignment) {
    patch32(at,name);patch32(at+4,kind);store64(output+at+8,flags);
    store64(output+at+16,address);store64(output+at+24,offset);
    store64(output+at+32,size);store64(output+at+48,alignment);return 0;
}
fn arm64_finish() {
    if a64_object {return arm64_object_finish();}
    a64_ir=output;a64_ir_size=output_size;
    a64_map=alloc(a64_ir_size/2);a64_fixups=alloc((a64_ir_size/16+1)*24);
    output=alloc(output_limit);output_size=0;vm_mode=0;
    if a64_map<0 || a64_fixups<0 || output<0 {fail("cannot allocate ARM64 code generation");}
    while output_size<4096 {emit(0);}
    // Kernel initial stack: argc followed by argv pointers, already aligned.
    a64_mem(0,0,31,0);a64_ins(0x910023e1); // ADD x1,sp,#8
    let main=find(functions,function_count,"main",4);
    a64_fix(load64(functions+main*32+16),1);
    a64_const(8,93);a64_ins(0xd4000001);a64_ins(0xd4200000);
    let i=0;while i<function_count {a64_function(i);i=i+1;}
    i=0;while i<a64_fixup_count {
        let fix=a64_fixups+i*24;let target=load64(fix+8);
        if target<0 || target>=a64_ir_size || target%16 {fail("invalid ARM64 relocation");}
        a64_patch_branch(load64(fix),load64(a64_map+target/2),load64(fix+16));i=i+1;
    }
    let code_end=output_size;
    if code_end> a64_data_base-0x400000 {fail("ARM64 code overlaps static data region");}
    while output_size%65536 {emit(0);}
    let data_at=output_size;i=0;
    while i<vm_heap_used {emit(load8(vm_heap+i));i=i+1;}
    let names=output_size;let text="\0.text\0.data\0.shstrtab\0";i=0;
    while i<23 {emit(load8(text+i));i=i+1;}
    while output_size%8 {emit(0);}
    let sections=output_size;i=0;while i<256 {emit(0);i=i+1;}
    a64_section(sections+64,1,1,6,0x401000,4096,code_end-4096,4);
    a64_section(sections+128,7,1,3,a64_data_base,data_at,vm_heap_used,8);
    a64_section(sections+192,13,3,0,0,names,23,1);
    // ELF64 LE ET_EXEC, EM_AARCH64; RX code, RW data, non-executable stack.
    patch32(0,0x464c457f);store8(output+4,2);store8(output+5,1);store8(output+6,1);
    store8(output+16,2);store8(output+18,183);patch32(20,1);
    store64(output+24,0x401000);store64(output+32,64);store64(output+40,sections);
    store8(output+52,64);store8(output+54,56);store8(output+56,3);
    store8(output+58,64);store8(output+60,4);store8(output+62,3);
    a64_segment(64,1,5,0,0x400000,code_end,65536);
    a64_segment(120,1,6,data_at,a64_data_base,vm_heap_used,65536);
    a64_segment(176,0x6474e551,6,0,0,0,16);
    return 0;
}
