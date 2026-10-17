import "../lib/arm64-code.flex";
// Leaf word-IR JIT. Code generation is platform independent; executable-memory
// publication/calls belong to the host. Caller owns code and scratch buffers.
// Context words: locals, fuel, error, backedges, deadline_ns, timespec[2],
// guest_heap, guest_heap_bytes. Errors match VM: 1=fuel,2=division,3=bounds,8=time.
// Compile results: positive byte count; -1=interpreter fallback; -2=bad IR;
// -3=insufficient buffer. No calls, raw pointer builtins, syscalls or FFI emitted.
global aj_code=0;
global aj_size=0;
global aj_capacity=0;
global aj_failed=0;
global aj_map=0;
global aj_heights=0;
global aj_branches=0;
global aj_slots=0;
global aj_depth=0;
global aj_error1=0;
global aj_error2=0;
global aj_error3=0;
global aj_error8=0;
global aj_remaining=0;
global aj_heap_end=0;
global aj_heap_base=0;
global aj_ir_bytes=0;
global aj_tail_fuel=0;
global aj_loop_body=0;
global aj_loop_backedge=0;
global aj_loop_condition=0;
global aj_loop_entry=0;
global aj_batch=0;
// Scratch heights pack depth in bits 0..15, prepaid block/trace fuel in
// 16..31, and the checked-copy entry branch + 1 in 32..63 after validation.
// Cached execution state: x12=heap, x13=heap bytes, x14=backedges,
// x15=deadline, x16=first declaration's array base, x17=its validity.
// Batch modes: 0=ordinary trace, 1=no deadline, 2=clock-enabled. No calls generated;
// Linux/Android's clock SVC preserves these caller-saved registers.

fn aj_ins(word) {
    if aj_size>aj_capacity-4 {aj_failed=1;return 0;}
    let i=0;while i<4 {store8(aj_code+aj_size+i,word>>(i*8));i=i+1;}
    aj_size=aj_size+4;return 0;
}
fn aj_patch(at,word) {
    if at<0 || at>aj_size-4 {aj_failed=1;return 0;}
    let i=0;while i<4 {store8(aj_code+at+i,word>>(i*8));i=i+1;}return 0;
}
fn aj_const(reg,value) {
    aj_ins(arm64_word_movz(reg,value));let shift=16;
    while shift<64 {let part=(value>>shift)&65535;if part {aj_ins(arm64_word_movk(reg,part,shift));}shift=shift+16;}
    return 0;
}
fn aj_mov(dst,src) {if dst==src {return 0;}return aj_ins(arm64_word_mov(dst,src));}
fn aj_rr(op,dst,left,right) {return aj_ins(arm64_word_rr(op,dst,left,right));}
fn aj_cmp(left,right) {return aj_ins(arm64_word_cmp(left,right));}
fn aj_mem(store,reg,base,offset) {return aj_ins(arm64_word_mem(store,reg,base,offset));}
fn aj_cond(condition) {let at=aj_size;aj_ins(arm64_word_cond(0,condition));return at;}
fn aj_patch_cond(at,to,condition) {
    let delta=to-at;if delta%4 || delta< -1048576 || delta>=1048576 {aj_failed=1;return 0;}
    return aj_patch(at,arm64_word_cond(delta,condition));
}
fn aj_local(store,reg,slot) {
    // Seven locals/temporaries remain in callee-saved x22..x28 across branches
    // and clock syscalls. Further slots spill below the 80-byte save area.
    if slot<7 {if store {return aj_mov(slot+22,reg);}return aj_mov(reg,slot+22);}
    let offset=(slot+4)*8;
    if offset<=256 {
        let word=0xf8400000;if store {word=0xf8000000;}
        return aj_ins(word|(((-offset)&511)<<12)|(29<<5)|reg);
    }
    aj_const(9,offset);aj_rr(0xcb000000,10,29,9);return aj_mem(store,reg,10,0);
}
fn aj_return() {
    aj_mem(1,21,19,8);aj_mem(1,14,19,24); // Publish fuel and backedges on every exit.
    aj_ins(0xd10143bf); // SUB sp,x29,#80
    aj_ins(0xa8c173fb); // LDP x27,x28,[sp],#16
    aj_ins(0xa8c16bf9); // LDP x25,x26,[sp],#16
    aj_ins(0xa8c163f7); // LDP x23,x24,[sp],#16
    aj_ins(0xa8c15bf5); // LDP x21,x22,[sp],#16
    aj_ins(0xa8c153f3); // LDP x19,x20,[sp],#16
    aj_ins(0xa8c17bfd);aj_ins(0xd65f03c0);return 0;
}
fn aj_error_branch(condition,error) {
    // Link pending conditional branches inside their own instruction words.
    // This needs no additional scratch storage; all guards share error exits.
    let previous=aj_error1;
    if error==2 {previous=aj_error2;}else if error==3 {previous=aj_error3;}else if error==8 {previous=aj_error8;}
    let head=aj_size+1;aj_ins((previous<<4)|(condition^1));
    if error==1 {aj_error1=head;}else if error==2 {aj_error2=head;}else if error==3 {aj_error3=head;}else {aj_error8=head;}
    return 0;
}
fn aj_guard(condition,error) {
    if aj_remaining>0 {
        // A fast block prepaid its fuel. Restore only the instructions after
        // this failing instruction, preserving precise VM errors/side effects.
        let pass=aj_cond(condition);aj_const(9,aj_remaining);
        aj_rr(0x8b000000,21,21,9);aj_error_branch(15,error);
        aj_patch_cond(pass,aj_size,condition);return 0;
    }
    return aj_error_branch(condition,error);
}
fn aj_read_word(at) {
    let word=0;let i=0;while i<4 {word=word|(load8(aj_code+at+i)<<(i*8));i=i+1;}
    return word;
}
fn aj_error_exit(head,error) {
    if !head {return 0;}
    let target=aj_size;
    if error==1 {aj_ins(0x910006b5);} // Undo the failing fuel subtraction.
    aj_const(9,error);aj_mem(1,9,19,16);aj_const(0,0);aj_return();
    if aj_failed {return 0;}
    while head {
        let at=head-1;let word=aj_read_word(at);
        aj_patch_cond(at,target,word&15);head=word>>4;
    }return 0;
}
fn aj_meter() {
    // SUBS and signed GE also handle MIN fuel via the overflow flag.
    // The shared exhaustion exit restores the unconsumed failing unit.
    aj_ins(0xf10006b5); // SUBS x21,x21,#1
    aj_guard(10,1);
    return 0;
}
fn aj_patch_cb(at,to,reg,nonzero) {
    if aj_failed {return 0;}
    aj_patch_cond(at,to,0);if aj_failed {return 0;}
    return aj_patch(at,(aj_read_word(at)^0xe0000000)|reg|(nonzero<<24));
}
fn aj_branch_ir(pc,condition) {
    let previous=load64(aj_branches+pc/2);
    store64(aj_branches+pc/2,aj_size+1);return aj_ins((previous<<4)|condition);
}
fn aj_clock() {
    aj_ins(0x910005ce); // ADD x14,x14,#1
    if aj_batch==1 {return 0;} // Entry proved that this batch has no deadline.
    let disabled=-1;
    if aj_batch!=2 {disabled=aj_size;aj_ins(0xb400000f);} // CBZ x15 (deadline disabled)
    aj_ins(0xf24025df); // TST x14,#1023
    let skip=aj_cond(1);
    aj_mov(20,0);aj_const(0,1);aj_ins(0x9100a261); // x1=context+40
    aj_const(8,113);aj_ins(0xd4000001);aj_cmp(0,31);aj_guard(10,8);
    aj_mem(0,9,19,40);aj_const(10,1000000000);aj_rr(0x9b007c00,9,9,10);
    aj_mem(0,10,19,48);aj_rr(0x8b000000,9,9,10);
    aj_cmp(9,15);aj_guard(11,8);aj_mov(0,20);
    aj_patch_cond(skip,aj_size,1);if disabled>=0 {aj_patch_cb(disabled,aj_size,15,0);}return 0;
}
fn aj_comparison(op) {
    if op==260 {return 1;}if op==60 {return 11;}if op==62 {return 12;}
    if op==261 {return 13;}if op==262 {return 10;}return 0;
}
fn aj_binary(op,dst,left,right,boolean) {
    if op==43 {aj_rr(0x8b000000,dst,left,right);}
    else if op==45 {aj_rr(0xcb000000,dst,left,right);}
    else if op==42 {aj_rr(0x9b007c00,dst,left,right);}
    else if op==47 || op==37 {
        aj_cmp(right,31);aj_guard(1,2);
        aj_const(9,-1);aj_cmp(right,9);let ordinary=aj_cond(1);
        aj_const(9,-9223372036854775807-1);aj_cmp(left,9);aj_guard(1,2);
        aj_patch_cond(ordinary,aj_size,1);
        aj_rr(0x9ac00c00,9,left,right);
        if op==37 {aj_ins(0x9b008000|(right<<16)|(left<<10)|(9<<5)|dst);}else {aj_mov(dst,9);}
    }else if op==38 {aj_rr(0x8a000000,dst,left,right);}
    else if op==124 {aj_rr(0xaa000000,dst,left,right);}
    else if op==94 {aj_rr(0xca000000,dst,left,right);}
    else if op==265 {aj_rr(0x9ac02000,dst,left,right);}
    else if op==266 {aj_rr(0x9ac02800,dst,left,right);}
    else {aj_cmp(left,right);if boolean {aj_ins(arm64_word_cset(dst,aj_comparison(op)));}}
    return 0;
}
fn aj_shift_add(value) {
    if value<3 {return 0;}let bits=value-1;let shift=0;
    while !(bits&1) {bits=bits>>1;shift=shift+1;}
    if bits==1 {return shift;}return 0;
}
fn aj_can_immediate(op,value) {
    if value>=0 && value<=4095 && (op==43 || op==45 || op==259 || op==260 || op==60 || op==62 || op==261 || op==262) {return 1;}
    if value>0 && (op==38 || op==124 || op==94) && !(value&(value+1)) {return 1;}
    return op==42 && aj_shift_add(value)>0;
}
fn aj_binary_immediate(op,dst,left,value,boolean) {
    if op==43 || op==45 {
        let word=0x91000000;if op==45 {word=0xd1000000;}
        aj_ins(word|(value<<10)|(left<<5)|dst);
    }else if op==42 {aj_ins(0x8b000000|(left<<16)|(aj_shift_add(value)<<10)|(left<<5)|dst);}
    else if op==38 || op==124 || op==94 {
        let bits=0;let n=value;while n {bits=bits+1;n=n>>1;}
        let word=0x92400000;if op==124 {word=0xb2400000;}else if op==94 {word=0xd2400000;}
        aj_ins(word|((bits-1)<<10)|(left<<5)|dst);
    }else {aj_ins(0xf100001f|(value<<10)|(left<<5));if boolean {aj_ins(arm64_word_cset(dst,aj_comparison(op)));}}
    return 0;
}
fn aj_local_source(reg,slot) {
    if slot<7 {return slot+22;}aj_local(0,reg,slot);return reg;
}
fn aj_operator(op) {
    return op==43 || op==45 || op==42 || op==47 || op==37 || op==38 || op==124 || op==94
        || op==265 || op==266 || op==259 || op==260 || op==60 || op==62 || op==261 || op==262;
}
fn aj_heap_address(end) {
    if end==aj_heap_end {if aj_batch {return 0;}aj_cmp(17,31);aj_guard(1,3);}
    else {aj_const(9,end);aj_cmp(13,9);aj_guard(2,3);aj_cmp(12,31);aj_guard(1,3);}
    return 0;
}
fn aj_acc_dead(ir,pc) {
    if pc<16 || pc>=aj_ir_bytes {return 0;}
    let op=load64(ir+pc);return op==1 || op==3 || op==5;
}
fn aj_emit_range(ir,start,end,fast) {
    let pc=start;let acc=0;let bound=-1;let immediate=0;let literal=0;
    // Register aliases are limited to an adjacent PUSH/load-or-constant/BIN
    // sequence; longer expressions keep their independent temporary slots.
    let pushed=-1;let pushed_pc=-1;let flags=-1;
    let checked_slot=-1;let checked_arg=0;
    while pc<end && !aj_failed {
        aj_depth=load64(aj_heights+pc/2)&65535;aj_remaining=0;
        if fast {aj_remaining=(end-pc)/16-1+aj_tail_fuel;}else {aj_meter();}
        let op=load64(ir+pc);let arg=load64(ir+pc+8);
        let previous_flags=flags;flags=-1;
        if op==1 {
            bound=-1;if arg>=0 {bound=arg;}
            immediate=0;
            if fast && pc+16<end && load64(ir+pc+16)==7 && aj_can_immediate(load64(ir+pc+24),arg) {immediate=1;literal=arg;}
            else {aj_const(0,arg);acc=0;}
        }else if op==2 {
            if aj_slots+aj_depth==checked_slot {checked_slot=-1;}
            let alias=0;
            if fast && pc+32<end && load64(ir+pc+32)==7 {
                let next=load64(ir+pc+16);let operand=load64(ir+pc+24);
                if acc>=22 {alias=next==1 || next==3;}
                else if next==3 && operand<7 {alias=1;}
                else if next==1 && aj_can_immediate(load64(ir+pc+40),operand) {alias=1;}
            }
            if alias {pushed=acc;pushed_pc=pc+32;}
            else {aj_local(1,acc,aj_slots+aj_depth);}
        }else if op==3 {
            bound=-1;
            if fast {acc=aj_local_source(0,arg);}else {aj_local(0,0,arg);}
        }else if op==4 {aj_local(1,acc,arg);if fast && arg<7 {acc=arg+22;}}
        else if op==5 || op==6 {
            aj_heap_address(arg+8);
            let reg=acc;if op==5 {reg=0;acc=0;bound=-1;}
            if fast && arg<=32760 {aj_mem(op==6,reg,12,arg);}
            else {aj_const(9,arg);aj_rr(0x8b000000,10,12,9);aj_mem(op==6,reg,10,0);}
        }else if op==21 || op==22 {
            let index=acc;
            if op==22 {
                let slot=aj_slots+aj_depth-1;
                if fast {index=aj_local_source(1,slot);}else {aj_local(0,1,slot);index=1;}
            }
            let span=arg>>32;let base=arg&4294967295;
            // A saved index cannot change while deeper expression slots are
            // used. Reuse only its successful load's identical declaration.
            let reuse=fast && op==22 && checked_slot==aj_slots+aj_depth-1 && checked_arg==arg;
            if !reuse {
                // Constants, comparisons and an AND with a nonnegative
                // constant prove an unsigned upper bound for a load index.
                if !(fast && op==21 && bound>=0 && bound<span) {
                    if fast && span<=4095 {aj_ins(0xf100001f|(span<<10)|(index<<5));}
                    else {aj_const(9,span);aj_cmp(index,9);}
                    aj_guard(3,3);
                }
                aj_heap_address(base+span*8);
            }
            if op==22 && checked_slot==aj_slots+aj_depth-1 {checked_slot=-1;}
            if fast && op==21 && pc>start && load64(ir+pc-16)==2 {checked_slot=aj_slots+aj_depth-1;checked_arg=arg;}
            let reg=acc;if op==21 {reg=0;acc=0;bound=-1;}
            if fast {
                let address=16;
                if base!=aj_heap_base {
                    address=10;
                    if base<=4095 {aj_ins(0x91000000|(base<<10)|(12<<5)|10);}
                    else {aj_const(9,base);aj_rr(0x8b000000,10,12,9);}
                }
                let word=0xf8607800;if op==22 {word=0xf8207800;}
                aj_ins(word|(index<<16)|(address<<5)|reg);
            }else {
                aj_const(9,base);aj_rr(0x8b000000,10,12,9);
                aj_ins(0x8b000c00|(index<<16)|(10<<5)|10);aj_mem(op==22,reg,10,0);
            }
        }else if op==7 {
            if aj_slots+aj_depth-1==checked_slot {checked_slot=-1;}
            let left=1;let dst=0;
            if fast {
                if pc==pushed_pc {left=pushed;}else {left=aj_local_source(1,aj_slots+aj_depth-1);}
                if pc+16<end && load64(ir+pc+16)==4 && load64(ir+pc+24)<7 {dst=load64(ir+pc+24)+22;}
            }else {aj_local(0,1,aj_slots+aj_depth-1);}
            let comparison=arg==259 || arg==260 || arg==60 || arg==62 || arg==261 || arg==262;
            let boolean=1;
            if fast && comparison && pc+16<end {
                let branch=load64(ir+pc+16);let target=load64(ir+pc+24);
                if (branch==11 || branch==12) && target>pc+16 && aj_acc_dead(ir,target) && aj_acc_dead(ir,pc+32) {boolean=0;}
            }
            if immediate {aj_binary_immediate(arg,dst,left,literal,boolean);immediate=0;}
            else {aj_binary(arg,dst,left,acc,boolean);}
            acc=dst;bound=-1;
            if comparison {bound=1;if fast {flags=aj_comparison(arg);}}
            else if arg==38 && pc>start && load64(ir+pc-16)==1 && load64(ir+pc-8)>=0 {bound=load64(ir+pc-8);}
        }else if op==9 {aj_mov(0,acc);acc=0;aj_return();}
        else if op==10 || op==11 || op==12 {
            if !(fast && op==10 && aj_acc_dead(ir,arg)) {aj_mov(0,acc);}acc=0;
            if arg<=pc {aj_clock();previous_flags=-1;}
            let condition=14;
            if op==11 || op==12 {
                if fast && previous_flags>=0 {condition=previous_flags;if op==11 {condition=condition^1;}}
                else {aj_cmp(0,31);condition=0;if op==12 {condition=1;}}
            }
            if fast && pc==aj_loop_condition && aj_batch {
                if aj_tail_fuel {
                    let next=aj_cond(condition^1);
                    aj_const(9,aj_tail_fuel);aj_rr(0x8b000000,21,21,9);
                    aj_branch_ir(pc,14);aj_patch_cond(next,aj_size,condition^1);
                }else {
                    aj_branch_ir(pc,condition);
                    aj_ins(arm64_word_branch(load64(aj_map+aj_loop_body/2)-aj_size,0));
                }
            }else if fast && pc==aj_loop_condition {
                aj_ins(arm64_word_cond(aj_loop_entry-aj_size,condition^1));
            }else if !(fast && pc==aj_loop_backedge) {aj_branch_ir(pc,condition);}
        }else if op==13 || op==15 {aj_cmp(acc,31);let condition=1;if op==15 {condition=0;}aj_ins(arm64_word_cset(0,condition));acc=0;bound=1;}
        else if op==14 {aj_rr(0xcb000000,0,31,acc);acc=0;bound=-1;}
        else if op==16 {aj_ins(0xaa2003e0|(acc<<16));acc=0;bound=-1;}
        pc=pc+16;
    }
    aj_mov(0,acc);aj_remaining=0;return 0;
}
fn aj_emit_batch_copies(ir,body,end,header,count,mode) {
    aj_batch=mode;let i=0;
    while i<4 && !aj_failed {
        let future=(3-i)*count;
        aj_tail_fuel=(body-header)/16+future;aj_emit_range(ir,body,end,1);
        aj_tail_fuel=future;aj_emit_range(ir,header,body,1);
        i=i+1;
    }
    aj_batch=0;aj_tail_fuel=0;return 0;
}
fn aj_emit_batch(ir,body,end,header,count) {
    // Guard the entire group before changing guest state. A rejected group
    // resumes the ordinary trace with its original fuel and accumulator.
    let heap=-1;if aj_heap_end {heap=aj_size;aj_ins(0xb4000011);} // CBZ x17
    let total=count*4;aj_ins(0xf1000000|(total<<10)|(21<<5)|21);
    let enough=aj_cond(10);
    aj_ins(0x91000000|(total<<10)|(21<<5)|21);
    let reject=aj_size;aj_ins(arm64_word_branch(0,0));
    aj_patch_cond(enough,aj_size,10);
    let deadline=aj_size;aj_ins(0xb500000f); // CBNZ x15 -> clock-enabled batch
    aj_emit_batch_copies(ir,body,end,header,count,1);
    aj_patch_cb(deadline,aj_size,15,1);
    aj_emit_batch_copies(ir,body,end,header,count,2);
    if heap>=0 {aj_patch_cb(heap,aj_size,17,0);}
    aj_patch(reject,arm64_word_branch(aj_size-reject,0));
    return 0;
}
fn arm64_jit_compile(ir,bytes,code,capacity,scratch,scratch_bytes) {
    if !ir || bytes<48 || bytes%16 || bytes>131072 || load64(ir)!=18 {return -2;}
    aj_slots=load64(ir+8);if aj_slots<0 || aj_slots>4096 {return -2;}
    if !code || !scratch || capacity<4 || capacity>1048576 || scratch_bytes<bytes/2*3 {return -3;}
    aj_code=code;aj_capacity=capacity;aj_size=0;aj_failed=0;
    aj_error1=0;aj_error2=0;aj_error3=0;aj_error8=0;aj_heap_end=0;aj_heap_base=0;aj_ir_bytes=bytes;
    aj_tail_fuel=0;aj_loop_body=0;aj_loop_backedge=0;aj_loop_condition=0;aj_loop_entry=0;aj_batch=0;
    aj_map=scratch;aj_heights=scratch+bytes/2;aj_branches=scratch+bytes;
    let pc=16;let maximum=0;aj_depth=0;
    while pc<bytes {
        let op=load64(ir+pc);let arg=load64(ir+pc+8);
        store64(aj_heights+pc/2,aj_depth);store64(aj_branches+pc/2,0);store64(aj_map+pc/2,0);
        if op==2 {if arg {return -2;}aj_depth=aj_depth+1;if aj_depth>maximum {maximum=aj_depth;}}
        else if op==3 || op==4 {if arg<0 || arg>=aj_slots {return -2;}}
        else if op==5 || op==6 {if arg<16 || arg>4294967287 || arg%8 {return -2;}if !aj_heap_end {aj_heap_end=arg+8;aj_heap_base=arg;}}
        else if op==21 || op==22 {
            let base=arg&4294967295;let span=arg>>32;
            if base<16 || base%8 || span<1 || span>(4294967295-base)/8 {return -2;}
            if op==22 {aj_depth=aj_depth-1;}
            if !aj_heap_end {aj_heap_end=base+span*8;aj_heap_base=base;}
        }else if op==7 {if !aj_operator(arg) {return -2;}aj_depth=aj_depth-1;}
        else if op==9 {if arg || aj_depth {return -2;}}
        else if op==10 || op==11 || op==12 {if arg<16 || arg>=bytes || arg%16 {return -2;}}
        else if op>=13 && op<=16 {if arg {return -2;}}
        else if op!=1 {return -1;}
        if aj_depth<0 {return -2;}
        if pc==bytes-16 && op!=9 && op!=10 {return -2;}
        pc=pc+16;
    }
    if aj_depth {return -2;}
    pc=16;while pc<bytes {
        let op=load64(ir+pc);let arg=load64(ir+pc+8);
        if (op==10 || op==11 || op==12) && load64(aj_heights+pc/2)!=load64(aj_heights+arg/2) {return -2;}
        pc=pc+16;
    }
    // Mark every branch target and fallthrough as a basic-block boundary.
    store64(aj_map+8,1);pc=16;
    while pc<bytes {
        let op=load64(ir+pc);
        if op==10 || op==11 || op==12 {store64(aj_map+load64(ir+pc+8)/2,1);}
        if op>=9 && op<=12 && pc+16<bytes {store64(aj_map+(pc+16)/2,1);}
        pc=pc+16;
    }
    aj_ins(0xa9bf7bfd);aj_ins(0x910003fd);aj_ins(0xa9bf53f3);
    aj_ins(0xa9bf5bf5);aj_ins(0xa9bf63f7);aj_ins(0xa9bf6bf9);aj_ins(0xa9bf73fb);
    aj_mov(19,0);aj_mem(0,21,19,8);
    let spilled=aj_slots+maximum-7;if spilled<0 {spilled=0;}
    aj_const(9,(spilled*8+15)& -16);aj_ins(0xcb2963ff);
    aj_mem(0,20,19,0);let i=0;
    while i<aj_slots {aj_mem(0,11,20,i*8);aj_local(1,11,i);i=i+1;}
    aj_mem(0,14,19,24);aj_mem(0,15,19,32);
    if aj_heap_end {
        aj_mem(0,12,19,56);aj_mem(0,13,19,64);
        aj_const(9,aj_heap_base);aj_rr(0x8b000000,16,12,9);
        aj_const(9,aj_heap_end);aj_cmp(13,9);aj_ins(arm64_word_cset(17,2));
        aj_cmp(12,31);aj_ins(arm64_word_cset(9,1));aj_rr(0x8a000000,17,17,9);
    }
    aj_const(0,0);pc=16;
    while pc<bytes && !aj_failed {
        let end=pc+16;
        while end<bytes && !load64(aj_map+end/2) {end=end+16;}
        store64(aj_map+pc/2,aj_size);
        if end==pc+16 {aj_emit_range(ir,pc,end,0);}
        else {
            let count=(end-pc)/16;let header=0;
            // Rotate a simple while loop: the body prepays its following
            // header, then branches directly back to the body on continuation.
            // The checked copy retains the original IR control flow.
            if load64(ir+end-16)==10 && pc>=32 && load64(ir+end-8)<pc {
                let candidate=load64(ir+end-8);let last=load64(ir+pc-16);
                if (last==11 || last==12) && load64(ir+pc-8)==end && load64(aj_map+candidate/2)>1 {
                    let scan=candidate+16;
                    while scan<pc && !load64(aj_map+scan/2) {scan=scan+16;}
                    if scan==pc {header=candidate;count=count+(pc-header)/16;}
                }
            }
            if header {
                aj_loop_body=pc;aj_loop_backedge=end-16;aj_loop_condition=pc-16;
                // Bounded code growth: four copies of a <=64-record trace per deadline mode.
                if count<=64 {aj_emit_batch(ir,pc,end,header,count);}
            }
            aj_loop_entry=aj_size;
            if count<=4095 {aj_ins(0xf1000000|(count<<10)|(21<<5)|21);}
            else {aj_const(9,count);aj_rr(0xeb000000,21,21,9);}
            let slow=aj_cond(11);
            store64(aj_heights+pc/2,load64(aj_heights+pc/2)|(count<<16)|((slow+1)<<32));
            if header {
                aj_loop_body=pc;aj_loop_backedge=end-16;aj_loop_condition=pc-16;
                aj_tail_fuel=(pc-header)/16;
            }
            aj_emit_range(ir,pc,end,1);
            if header {aj_tail_fuel=0;aj_emit_range(ir,header,pc,1);}
            aj_loop_body=0;aj_loop_backedge=0;aj_loop_condition=0;aj_loop_entry=0;
        }
        pc=end;
    }
    if aj_failed {return -3;}
    // Place checked copies after all hot blocks, outside normal loop layout.
    pc=16;
    while pc<bytes && !aj_failed {
        let end=pc+16;while end<bytes && !load64(aj_map+end/2) {end=end+16;}
        let slow=load64(aj_heights+pc/2)>>32;
        if slow {
            aj_patch_cond(slow-1,aj_size,11);
            let count=(load64(aj_heights+pc/2)>>16)&65535;
            if count<=4095 {aj_ins(0x91000000|(count<<10)|(21<<5)|21);}
            else {aj_const(9,count);aj_rr(0x8b000000,21,21,9);}
            aj_emit_range(ir,pc,end,0);
            let last=load64(ir+end-16);
            if last!=9 && last!=10 {aj_ins(arm64_word_branch(load64(aj_map+end/2)-aj_size,0));}
        }
        pc=end;
    }
    if aj_failed {return -3;}
    aj_error_exit(aj_error1,1);aj_error_exit(aj_error2,2);
    aj_error_exit(aj_error3,3);aj_error_exit(aj_error8,8);
    if aj_failed {return -3;}
    pc=16;while pc<bytes {
        let head=load64(aj_branches+pc/2);
        while head {
            let at=head-1;let word=aj_read_word(at);head=word>>4;
            let delta=load64(aj_map+load64(ir+pc+8)/2)-at;
            if (word&15)==14 {aj_patch(at,arm64_word_branch(delta,0));}
            else {aj_patch_cond(at,at+delta,word&15);}
        }
        pc=pc+16;
    }
    if aj_failed {return -3;}return aj_size;
}
