// Shared effects for valid, resolved word IR. No target names or registers.
// Bits: pointer read 1, pointer write 2, global read 4, global write 8,
// allocation 16, external I/O 32, synchronization 64, nondeterminism 128,
// possible trap 256, possible nontermination 512, unknown operation 1024.
// Overrides: -1 means inspect the body, otherwise use a trusted target mask.
// A zero summary is a sufficient (not necessary) proof of an effect-free call.
global ir_effect_all=2047;
global ie_count=0;
global ie_ready=0;
global ie_nodes=0;
global ie_edges=0;
global ie_queue=0;
global ie_stack=0;
global ie_node_capacity=0;
global ie_edge_capacity=0;
global ie_used=0;
// Nodes: effects, outgoing edge head, incoming head, DFS color, queued flag.
// Edges: caller, callee, outgoing next, incoming next. Heads are index+1.
fn ir_effect_get(index) {
    if !ie_ready || index<0 || index>=ie_count {return ir_effect_all;}
    return load64(ie_nodes+index*40);
}
fn ie_add(caller,callee) {
    let edge=ie_edges+ie_used*32;ie_used=ie_used+1;
    let from=ie_nodes+caller*40;let to=ie_nodes+callee*40;
    store64(edge,caller);store64(edge+8,callee);
    store64(edge+16,load64(from+8));store64(edge+24,load64(to+16));
    store64(from+8,ie_used);store64(to+16,ie_used);return 0;
}
fn ie_instruction(op,arg,pc,start,end,slots) {
    if op==3 || op==4 {if arg<0 || arg>=slots {return ir_effect_all;}return 0;}
    if op==5 {return 4;}if op==6 {return 8;}
    if op==21 {return 4|256;}if op==22 {return 8|256;}
    if op==7 {
        if arg==47 || arg==37 {return 256;}
        if arg==43 || arg==45 || arg==42 || arg==38 || arg==124 || arg==94 || arg==265 || arg==266
            || arg==259 || arg==260 || arg==60 || arg==62 || arg==261 || arg==262 {return 0;}
        return ir_effect_all;
    }
    if op>=10 && op<=12 {
        if arg<start || arg>=end || arg%16 {return ir_effect_all;}
        if arg<=pc {return 512;}return 0;
    }
    if op==17 {
        if arg==1 || arg==2 {return 1|256;}
        if arg==3 || arg==4 {return 2|256;}
        if arg==5 {return 16|256;}
        // Syscalls and FFI can touch arbitrary memory, block or never return.
        return ir_effect_all;
    }
    if op==19 || op==20 {return 32|128|256|512;}
    if op==0 || op==1 || op==2 || op==9 || (op>=13 && op<=16) || op==23 || op==28 {return 0;}
    return ir_effect_all;
}
fn ir_effect_analyze(code,size,table,count,overrides) {
    ie_ready=0;ie_count=count;ie_used=0;
    if size<0 || size%16 || count<0 || count>65536 || size/16>1048576 {return 0;}
    if !count {if size {return 0;}ie_ready=1;return 1;}
    if count>ie_node_capacity {
        let n=256;while n<count {n=n*2;}let data=alloc(n*64);
        if data<0 {return 0;}ie_nodes=data;ie_queue=data+n*40;ie_stack=data+n*48;ie_node_capacity=n;
    }
    let edge_count=0;let pc=0;while pc<size {if load64(code+pc)==8 {edge_count=edge_count+1;}pc=pc+16;}
    if edge_count>ie_edge_capacity {let n=256;while n<edge_count {n=n*2;}let data=alloc(n*32);
        if data<0 {return 0;}ie_edges=data;ie_edge_capacity=n;
    }
    let i=0;while i<count {let n=ie_nodes+i*40;let k=0;while k<40 {store64(n+k,0);k=k+8;}i=i+1;}
    if load64(table+16)!=0 {return 0;}
    i=0;while i<count {
        let start=load64(table+i*32+16);let end=size;if i+1<count {end=load64(table+(i+1)*32+16);}
        if start<0 || start%16 || end<=start || end>size || end%16 || load64(code+start)!=18 {return 0;}
        let slots=load64(code+start+8);let arity=load64(table+i*32+24);
        if slots<0 || slots>4096 || arity<0 || arity>slots {return 0;}
        let mask=0;let override=-1;if overrides {override=load64(overrides+i*8);}
        if override!=(-1) {if override<0 || (override&ir_effect_all)!=override {return 0;}mask=override;}
        else {pc=start+16;while pc<end {
            let op=load64(code+pc);let arg=load64(code+pc+8);
            if op==8 {if arg<0 || arg>=count {return 0;}ie_add(i,arg);}
            else {mask=mask|ie_instruction(op,arg,pc,start,end,slots);}pc=pc+16;
        }}store64(ie_nodes+i*40,mask);i=i+1;
    }
    // Iterative DFS: a back edge proves a recursive cycle. Mark its caller;
    // reverse propagation below marks the whole cycle and all its callers.
    i=0;while i<count {
        if !load64(ie_nodes+i*40+24) {
            let depth=1;store64(ie_nodes+i*40+24,1);store64(ie_stack,i);store64(ie_stack+8,load64(ie_nodes+i*40+8));
            while depth {let frame=ie_stack+(depth-1)*16;let node=load64(frame);let head=load64(frame+8);
                if !head {store64(ie_nodes+node*40+24,2);depth=depth-1;}
                else {let edge=ie_edges+(head-1)*32;store64(frame+8,load64(edge+16));let to=load64(edge+8);let color=load64(ie_nodes+to*40+24);
                    if color==1 {store64(ie_nodes+node*40,load64(ie_nodes+node*40)|256|512);}
                    else if !color {store64(ie_nodes+to*40+24,1);store64(ie_stack+depth*16,to);store64(ie_stack+depth*16+8,load64(ie_nodes+to*40+8));depth=depth+1;}
                }
            }
        }i=i+1;
    }
    // Monotone union through reverse edges. The bounded circular worklist
    // contains each function at most once; each effect bit only grows.
    i=0;while i<count {store64(ie_queue+i*8,i);store64(ie_nodes+i*40+32,1);i=i+1;}
    let read=0;let write=0;let pending=count;
    while pending {let child=load64(ie_queue+read*8);read=(read+1)%count;pending=pending-1;
        let node=ie_nodes+child*40;store64(node+32,0);let mask=load64(node);let head=load64(node+16);
        while head {let edge=ie_edges+(head-1)*32;let parent=load64(edge);let caller=ie_nodes+parent*40;let old=load64(caller);
            if (old|mask)!=old {store64(caller,old|mask);if !load64(caller+32) {store64(caller+32,1);store64(ie_queue+write*8,parent);write=(write+1)%count;pending=pending+1;}}
            head=load64(edge+24);
        }
    }
    ie_ready=1;return 1;
}
