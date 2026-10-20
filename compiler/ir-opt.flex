import "ir-effects.flex";
import "ir-effect-targets.flex";
import "ir-cse.flex";
// Shared optimizations on resolved accumulator/stack word IR. No target
// instruction encodings or register assumptions belong in these passes.
global ir_opt_enabled=1;
global ir_opt_before=0;
global ir_opt_after=0;
global ir_opt_folds=0;
global ir_opt_branches=0;
global ir_opt_dead=0;
global io_code=0;
global io_flags=0;
global io_map=0;
global io_work=0;
global io_arena=0;
global io_capacity=0;
fn ir_opt_select(value) {
    if up_text(value,"basic") {ir_opt_enabled=1;}
    else if up_text(value,"none") {ir_opt_enabled=0;}
    else {fail("expected basic or none IR optimization mode");}return 0;
}
fn io_live(pc) {return load8(io_flags+pc/16)&1;}
fn io_drop(pc) {store8(io_flags+pc/16,load8(io_flags+pc/16)&254);return 0;}
fn io_boundary(pc) {store8(io_flags+pc/16,load8(io_flags+pc/16)|2);return 0;}
fn io_op(pc) {return load64(io_code+pc);}
fn io_arg(pc) {return load64(io_code+pc+8);}
fn io_set(pc,op,arg) {store64(io_code+pc,op);store64(io_code+pc+8,arg);return 0;}
fn io_comparison(op) {return op==259 || op==260 || op==60 || op==62 || op==261 || op==262;}
fn io_fold(start,end) {
    let depth=0;let pc=start;
    while pc<end {
        if load8(io_flags+pc/16)&2 {depth=0;}
        store64(io_work+depth*8,pc);depth=depth+1;let changed=1;
        while changed && depth>=2 {
            changed=0;let b=load64(io_work+(depth-1)*8);let a=load64(io_work+(depth-2)*8);
            let op=io_op(b);let value=io_arg(a);
            if io_op(a)==1 && op>=13 && op<=16 {
                if op==13 {value=value!=0;}else if op==14 {value=-value;}else if op==15 {value=!value;}else {value=~value;}
                io_set(a,1,value);io_drop(b);depth=depth-1;changed=1;ir_opt_folds=ir_opt_folds+1;
            }else if io_op(a)==1 && op==1 {
                io_drop(a);store64(io_work+(depth-2)*8,b);depth=depth-1;changed=1;ir_opt_folds=ir_opt_folds+1;
            }else if op==13 && (io_op(a)==13 || io_op(a)==15 || (io_op(a)==7 && io_comparison(io_arg(a)))) {
                io_drop(b);depth=depth-1;changed=1;ir_opt_folds=ir_opt_folds+1;
            }else if io_op(a)==1 && (op==11 || op==12) {
                let taken=value==0;if op==12 {taken=value!=0;}
                if taken {io_set(b,10,io_arg(b));}else {io_drop(b);depth=depth-1;}
                ir_opt_branches=ir_opt_branches+1;
            }else if depth>=4 && op==7 {
                let c=load64(io_work+(depth-3)*8);let first=load64(io_work+(depth-4)*8);
                if io_op(first)==1 && io_op(c)==2 && io_op(a)==1 {
                    let left=io_arg(first);let right=value;let binary_op=io_arg(b);
                    // Preserve division traps and wrapping/signed word semantics.
                    if (binary_op!=47 && binary_op!=37) || (right && !(left==0x8000000000000000 && right==(-1))) {
                        io_set(first,1,word_binary_result(binary_op,left,right));io_drop(c);io_drop(a);io_drop(b);
                        depth=depth-3;changed=1;ir_opt_folds=ir_opt_folds+1;
                    }
                }
            }
        }pc=pc+16;
    }return 0;
}
fn io_next(pc,end) {while pc<end && !io_live(pc) {pc=pc+16;}return pc;}
fn io_thread(start,end) {
    let pc=start;while pc<end {
        let op=io_op(pc);
        if io_live(pc) && op>=10 && op<=12 {
            let original=io_arg(pc);let target=io_next(original,end);let rounds=0;
            while target<end && io_op(target)==10 && io_arg(target)!=target && rounds<64 {
                target=io_next(io_arg(target),end);rounds=rounds+1;
            }
            if target!=original {io_set(pc,op,target);ir_opt_branches=ir_opt_branches+1;}
            if op==10 && target==io_next(pc+16,end) {io_drop(pc);ir_opt_branches=ir_opt_branches+1;}
        }pc=pc+16;
    }return 0;
}
fn io_enqueue(pc,end,used) {
    pc=io_next(pc,end);if pc>=end {fail("IR optimizer edge exceeds function");}
    if !(load8(io_flags+pc/16)&4) {store8(io_flags+pc/16,load8(io_flags+pc/16)|4);store64(io_work+used*8,pc);return used+1;}
    return used;
}
fn io_reach(start,end) {
    let used=io_enqueue(start,end,0);let read=0;
    while read<used {
        let pc=load64(io_work+read*8);read=read+1;let op=io_op(pc);
        if op>=10 && op<=12 {used=io_enqueue(io_arg(pc),end,used);}
        if op!=9 && op!=10 {used=io_enqueue(pc+16,end,used);}
    }
    let pc=start;while pc<end {
        if io_live(pc) && !(load8(io_flags+pc/16)&4) {io_drop(pc);ir_opt_dead=ir_opt_dead+1;}
        pc=pc+16;
    }return 0;
}
fn ir_optimize() {
    ie_ready=0;
    ir_opt_before=output_size/16;ir_opt_after=ir_opt_before;ir_opt_folds=0;ir_opt_branches=0;ir_opt_dead=0;ir_opt_cse=0;
    // Source transformation snapshots and serialized FIR remain the original
    // validated representation. Native source emission has its own pipeline.
    if !ir_opt_enabled || tx_recording || frontend_ir_target {return 0;}
    ir_effect_prepare();
    let size=output_size;let count=size/16;if !count {return 0;}
    // Reuse scratch without requiring a raw munmap capability when this
    // compiler itself runs inside a restricted VM or WebAssembly host.
    if count>io_capacity {let capacity=io_capacity;if !capacity {capacity=256;}while capacity<count {capacity=capacity*2;}
        io_arena=alloc(capacity*33+8);if io_arena<0 {fail("cannot allocate shared IR optimization");}io_capacity=capacity;
    }
    io_code=io_arena;io_flags=io_code+io_capacity*16;io_map=io_flags+io_capacity;io_work=io_map+(io_capacity+1)*8;
    net_copy(io_code,output,size);let pc=0;
    while pc<size {store8(io_flags+pc/16,1);pc=pc+16;}
    pc=0;while pc<size {let op=io_op(pc);
        if op>=10 && op<=12 {io_boundary(io_arg(pc));}
        if (op>=9 && op<=12) && pc+16<size {io_boundary(pc+16);}pc=pc+16;
    }
    let i=0;while i<function_count {
        let start=load64(functions+i*32+16);let end=size;if i+1<function_count {end=load64(functions+(i+1)*32+16);}
        io_boundary(start);io_boundary(start+16);io_fold(start,end);io_cse(start,end);
        // RDNA derives execution-mask reconvergence from structured branch
        // joins. Threading an edge through a join can bypass mask restoration
        // even though scalar CFG semantics are unchanged. Retain those edges
        // until this backend carries explicit reconvergence metadata.
        if hp_machine!=2 {io_thread(start,end);}io_reach(start,end);i=i+1;
    }
    let bytes=0;pc=0;while pc<size {store64(io_map+pc/2,bytes);if io_live(pc) {bytes=bytes+16;}pc=pc+16;}store64(io_map+size/2,bytes);
    // Reuse writable output, but never overwrite a serialized FIR input blob.
    if frontend_blob && output>=frontend_blob && output<frontend_blob+frontend_blob_size {
        output=alloc(size);if output<0 {fail("cannot allocate optimized FIR instructions");}
    }
    // Only io_code is rewritten until every old PC has a mapping. Function
    // names and the serialized frontend representation remain untouched.
    pc=0;while pc<size {
        if io_live(pc) {let op=io_op(pc);let arg=io_arg(pc);if op>=10 && op<=12 {arg=load64(io_map+arg/2);}
            let at=load64(io_map+pc/2);store64(output+at,op);store64(output+at+8,arg);}
        pc=pc+16;
    }
    i=0;while i<function_count {let f=functions+i*32;store64(f+16,load64(io_map+load64(f+16)/2));i=i+1;}
    let calls_used=0;i=0;while i<call_count {let c=calls+i*32;let at=load64(c+16)-8;
        if io_live(at) {store64(c+16,load64(io_map+at/2)+8);net_copy(calls+calls_used*32,c,32);calls_used=calls_used+1;}i=i+1;
    }
    call_count=calls_used;output_size=bytes;ir_opt_after=bytes/16;
    return 0;
}
fn ir_opt_stats() {
    print(2,"IR instructions: ");print_number(ir_opt_before);print(2," -> ");print_number(ir_opt_after);
    print(2,"; constant folds: ");print_number(ir_opt_folds);print(2,"; branch rewrites: ");print_number(ir_opt_branches);
    print(2,"; dead instructions: ");print_number(ir_opt_dead);print(2,"; common expressions: ");print_number(ir_opt_cse);print(2,"\n");
    if ie_ready {let pure=0;let traps=0;let diverge=0;let i=0;while i<ie_count {let effect=ir_effect_get(i);
        if !effect {pure=pure+1;}if effect&256 {traps=traps+1;}if effect&512 {diverge=diverge+1;}i=i+1;}
        print(2,"IR effects: ");print_number(pure);print(2," effect-free functions; ");print_number(traps);print(2," may trap; ");print_number(diverge);print(2," may not return\n");
    }return 0;
}
