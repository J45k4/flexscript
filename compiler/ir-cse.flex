// Local value numbering for pure word arithmetic. Reuse a result only while
// an existing local still holds it; no synthetic locals or new IR opcodes.
global ir_opt_cse=0;
global ic_table=0;
global ic_locals=0;
global ic_stack=0;
global ic_capacity=0;
global ic_generation=0;
global ic_fresh=4096;
fn ic_unknown() {ic_fresh=ic_fresh+1;return -ic_fresh;}
fn ic_reset(depth) {
    ic_generation=ic_generation+1;let i=0;
    // Pending operands may survive a call or a CFG boundary, but their old
    // table identities and removable producer spans do not.
    while i<depth {store64(ic_stack+i*32,ic_unknown());store64(ic_stack+i*32+24,0);i=i+1;}
    return 0;
}
fn ic_value(kind,left,right) {
    // Bounded probing makes pathological blocks lose opportunities rather
    // than turning compilation into a quadratic expression-table search.
    let hash=((left*1000003)^(right*9176)^(kind*97))&4095;let probes=0;
    while probes<32 {let node=ic_table+hash*40;
        if load64(node)!=ic_generation {store64(node,ic_generation);store64(node+8,kind);store64(node+16,left);store64(node+24,right);store64(node+32,0);return node;}
        if load64(node+8)==kind && load64(node+16)==left && load64(node+24)==right {return node;}
        hash=(hash+1)&4095;probes=probes+1;
    }return ic_unknown();
}
fn ic_binary(op) {
    return op==43 || op==45 || op==42 || op==38 || op==124 || op==94
        || op==265 || op==266 || io_comparison(op);
}
fn ic_commutative(op) {return op==43 || op==42 || op==38 || op==124 || op==94 || op==259 || op==260;}
fn ic_replace(value,begin,pc,pure) {
    if !pure || value<=0 {return 0;}let holder=load64(value+32);if !holder {return 0;}
    let local=ic_locals+(holder-1)*16;
    if load64(local)!=ic_generation || load64(local+8)!=value {return 0;}
    let at=begin;while at<pc {io_drop(at);at=at+16;}io_set(pc,3,holder-1);ir_opt_cse=ir_opt_cse+1;return 1;
}
fn io_cse(start,end) {
    let slots=io_arg(start);if slots<0 || slots>4096 {return 0;}
    if !ic_table {ic_table=alloc(4096*40);ic_locals=alloc(4096*16);if ic_table<0 || ic_locals<0 {fail("cannot allocate IR value numbering");}}
    let needed=(end-start)/16;if needed>65536 {needed=65536;}
    if needed>ic_capacity {ic_stack=alloc(needed*32);if ic_stack<0 {fail("cannot allocate IR value stack");}ic_capacity=needed;}
    let depth=0;ic_reset(0);let value=ic_unknown();let begin=start;let pure=0;let pc=start+16;
    while pc<end {
        if load8(io_flags+pc/16)&2 {ic_reset(depth);value=ic_unknown();pure=0;}
        if io_live(pc) {let op=io_op(pc);let arg=io_arg(pc);
            if op==1 {value=ic_value(1,arg,0);begin=pc;pure=1;}
            else if op==3 || op==4 {
                if arg<0 || arg>=slots {return 0;}let local=ic_locals+arg*16;
                if op==3 {if load64(local)!=ic_generation {store64(local,ic_generation);store64(local+8,-arg-1);}value=load64(local+8);begin=pc;pure=1;}
                else {store64(local,ic_generation);store64(local+8,value);if value>0 {store64(value+32,arg+1);}pure=0;}
            }else if op==2 {
                if depth>=ic_capacity {return 0;}let entry=ic_stack+depth*32;store64(entry,value);store64(entry+8,begin);store64(entry+16,pc);store64(entry+24,pure);depth=depth+1;pure=0;
            }else if op==7 {
                if !depth {return 0;}depth=depth-1;let entry=ic_stack+depth*32;let left=load64(entry);
                pure=pure && load64(entry+24) && begin==io_next(load64(entry+16)+16,end);begin=load64(entry+8);
                if ic_binary(arg) {
                    if ic_commutative(arg) && left>value {let swap=left;left=value;value=swap;}
                    value=ic_value(arg+256,left,value);if ic_replace(value,begin,pc,pure) {begin=pc;}
                }else {
                    // Division/remainder and unknown operators stay in place,
                    // preserving their traps even inside larger expressions.
                    value=ic_unknown();pure=0;
                }
            }else if op>=13 && op<=16 {
                value=ic_value(op,value,0);if ic_replace(value,begin,pc,pure) {begin=pc;}
            }else {
                if op==8 {depth=depth-load64(functions+arg*32+24);}
                else if op==17 {let arity=7;if arg==1 || arg==2 || arg==5 || arg==7 {arity=1;}else if arg==3 || arg==4 || arg==8 {arity=2;}depth=depth-arity;}
                else if op==22 {depth=depth-1;}
                if depth<0 {return 0;}
                if op==8 && !ir_effect_get(arg) {
                    // Retain local arithmetic identities across proven
                    // effect-free calls, but never delete the call or its
                    // argument evaluation as part of a producer span.
                    let j=0;while j<depth {store64(ic_stack+j*32+24,0);j=j+1;}
                }else {ic_reset(depth);}
                value=ic_unknown();pure=0;
            }
        }pc=pc+16;
    }return 0;
}
