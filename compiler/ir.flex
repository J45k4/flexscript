// The portable FIR1 boundary is deliberately smaller than the trusted VM IR.
// Validate every instruction before any backend consumes extension output.
fn ir_bad() {fail("invalid frontend IR (FIR)");return 0;}
fn ir_operator(op) {
    return op==43 || op==45 || op==42 || op==47 || op==37 || op==38 || op==124 || op==94
        || op==265 || op==266 || op==259 || op==260 || op==60 || op==62 || op==261 || op==262;
}
fn ir_accept(blob,size) {
    if size<64 || size>4194304 {ir_bad();}
    let count=load64(blob+16);let code_at=load64(blob+24);let code_size=load64(blob+32);
    let names_at=load64(blob+40);let names_size=load64(blob+48);
    let profile=load64(blob);let state_count=load64(blob+56);
    if (profile!=0x31524946 && profile!=0x32524946 && profile!=0x33524946) || load64(blob+8)!=size
        || state_count<0 || state_count>262144 || (profile==0x32524946 && state_count>2048) || (profile==0x31524946 && state_count)
        || count<1 || count>2048 || code_at!=64+count*64 || code_size<48 || code_size%16
        || code_size>size-code_at || names_at!=code_at+code_size || names_size<0 || names_size!=size-names_at-state_count*8 {ir_bad();}
    let code=blob+code_at;let heights=alloc(code_size/2);let visited=alloc(code_size/2);let queue=alloc(code_size/2);
    if heights<0 || visited<0 || queue<0 {fail("cannot validate frontend IR");}
    let i=0;
    while i<count {
        let f=blob+64+i*64;let name=load64(f);let n=load64(f+8);let start=load64(f+16);
        let arity=load64(f+24);let slots=load64(f+32);let end=code_size;
        if i+1<count {end=load64(f+80);}
        if name<0 || n<1 || n>255 || name>names_size-n || start<0 || start>code_size-48 || start%16 || end%16
            || end>code_size || end<start+48 || (i==0 && start!=0) || arity<0 || arity>slots || slots>4096
            || load64(f+40) || load64(f+48) || load64(f+56) {ir_bad();}
        let k=0;while k<n {let c=load8(blob+names_at+name+k);if (!letter(c) && (k==0 || !digit(c))) {ir_bad();}k=k+1;}
        if find(functions,i,blob+names_at+name,n)>=0 {ir_bad();}
        let entry=functions+i*32;store64(entry,blob+names_at+name);store64(entry+8,n);store64(entry+16,start);store64(entry+24,arity);
        if load64(code+start)!=18 || load64(code+start+8)!=slots || load64(code+start+16)!=1 || load64(code+start+24)!=0 {ir_bad();}
        let pc=start+16;let stack=0;
        while pc<end {
            let op=load64(code+pc);let arg=load64(code+pc+8);store64(heights+pc/2,stack);
            if op==2 {if arg {ir_bad();}stack=stack+1;}
            else if op==3 || op==4 {if arg<0 || arg>=slots {ir_bad();}}
            else if op==5 || op==6 {if (profile!=0x32524946 && profile!=0x33524946) || arg<0 || arg>=state_count {ir_bad();}}
            else if op==21 || op==22 {
                let base=arg&4294967295;let span=arg>>32;
                if profile!=0x33524946 || span<1 || span>state_count || base>state_count-span {ir_bad();}
                if op==22 {stack=stack-1;}
            }
            else if op==19 || op==20 {if (profile!=0x32524946 && profile!=0x33524946) || arg {ir_bad();}}
            else if op==7 {if !ir_operator(arg) {ir_bad();}stack=stack-1;}
            else if op==8 {
                if arg<0 || arg>=count {ir_bad();}
                stack=stack-load64(blob+64+arg*64+24);
            }else if op==10 || op==11 || op==12 {if arg<start+16 || arg>=end || arg%16 {ir_bad();}}
            else if op==9 || (op>=13 && op<=16) {if arg || (op==9 && stack) {ir_bad();}}
            else if op!=1 {ir_bad();}
            if pc==end-16 && op!=9 && op!=10 {ir_bad();}
            if stack<0 || stack>65536 {ir_bad();}pc=pc+16;
        }
        if stack {ir_bad();}
        // Reachable edges must agree on expression stack height. Mark on enqueue
        // so the worklist cannot grow beyond the number of instructions.
        let read=0;let used=1;store64(queue,start+16);store64(visited+(start+16)/2,1);
        while read<used {
            pc=load64(queue+read*8);read=read+1;let op=load64(code+pc);let arg=load64(code+pc+8);
            stack=load64(heights+pc/2);if op==2 {stack=stack+1;}else if op==7 {stack=stack-1;}
            else if op==22 {stack=stack-1;}else if op==8 {stack=stack-load64(blob+64+arg*64+24);}
            let edge=0;let edges=1;if op==9 {edges=0;}else if op==11 || op==12 {edges=2;}
            while edge<edges {
                let target=pc+16;if op==10 || (edges==2 && edge==1) {target=arg;}
                if target>=end || load64(heights+target/2)!=stack {ir_bad();}
                if !load64(visited+target/2) {store64(visited+target/2,1);store64(queue+used*8,target);used=used+1;}
                edge=edge+1;
            }
        }
        i=i+1;
    }
    syscall(11,heights,code_size/2,0,0,0,0);syscall(11,visited,code_size/2,0,0,0,0);syscall(11,queue,code_size/2,0,0,0,0);
    frontend_blob=blob;frontend_blob_size=size;
    output=code;output_size=code_size;function_count=count;global_count=0;call_count=0;
    if profile==0x32524946 || profile==0x33524946 {
        if !vm_heap {vm_heap=alloc(vm_heap_limit);if vm_heap<0 {fail("cannot allocate IR state");}}
        let state_base=vm_heap_used;let address=vm_allocate(state_count*8+8);if address<0 {fail("IR state exceeds VM memory");}
        net_copy(vm_address(address,state_count*8+8),blob+names_at+names_size,state_count*8);
        output=alloc(code_size);if output<0 {fail("cannot allocate IR instructions");}net_copy(output,code,code_size);
        i=0;while i<code_size {let op=load64(output+i);if op==5 || op==6 {store64(output+i+8,address+load64(output+i+8)*8);}else if op==21 || op==22 {let arg=load64(output+i+8);store64(output+i+8,(arg& -4294967296)|(state_base+(arg&4294967295)*8));}i=i+16;}
    }
    let main=find(functions,count,"main",4);if main<0 {fail("missing main function");}
    if load64(functions+main*32+24) {fail("portable IR main must take zero parameters");}
    return 0;
}
fn ir_native() {
    let code=output;let size=output_size;let entries=alloc(function_count*8);let map=alloc(size/2);
    let branches=alloc(size);let used=0;let i=0;
    if entries<0 || map<0 || branches<0 {fail("cannot allocate native IR lowering");}
    while i<function_count {store64(entries+i*8,load64(functions+i*32+16));i=i+1;}
    output=alloc(67108864);if output<0 {fail("cannot allocate native output");}output_size=0;vm_mode=0;initialize_output();
    let state_at=output_size;let k=16;while k<vm_heap_used {emit(load8(vm_heap+k));k=k+1;}
    i=0;while i<function_count {
        let f=functions+i*32;let start=load64(entries+i*8);let end=size;
        if i+1<function_count {end=load64(entries+(i+1)*8);}
        let slots=load64(code+start+8);let arity=load64(f+24);store64(f+16,output_size);
        emit(85);emit(72);emit(137);emit(229);emit(72);emit(129);emit(236);emit32(((slots*8+15)/16)*16);
        immediate(0);let k=0;while k<slots {vm_jit_local(k,1);k=k+1;}
        k=0;while k<arity {emit(72);emit(139);emit(133);emit32(16+(arity-k-1)*8);vm_jit_local(k,1);k=k+1;}
        let pc=start+16;while pc<end {
            store64(map+pc/2,output_size);let op=load64(code+pc);let arg=load64(code+pc+8);
            if op==1 {immediate(arg);}else if op==2 {push_value();}
            else if op==3 || op==4 {vm_jit_local(arg,op==4);}
            else if op==5 || op==6 {
                emit(72);emit(186);emit64(4194304+state_at+arg-16);emit(72);if op==5 {emit(139);}else {emit(137);}emit(2);
            }else if op==21 || op==22 {
                let base=4194304+state_at+(arg&4294967295)-16;let span=arg>>32;
                if op==21 {emit(72);emit(137);emit(193);}else {emit(89);} // rcx = index
                emit(72);emit(129);emit(249);emit32(span);let safe=jump(130);emit(15);emit(11);patch_jump(safe);
                emit(72);emit(186);emit64(base);emit(72);if op==21 {emit(139);}else {emit(137);}emit(4);emit(202);
            }else if op==19 || op==20 {ir_native_word_io(op==20);}
            else if op==7 {binary(arg);}else if op==9 {epilogue();}
            else if op==8 {
                if call_count>=65536 {fail("too many calls");}
                let target=functions+arg*32;let site=calls+call_count*32;call_count=call_count+1;
                store64(site,load64(target));store64(site+8,load64(target+8));store64(site+24,load64(target+24));
                emit(232);store64(site+16,output_size);emit32(0);
                if load64(target+24) {emit(72);emit(129);emit(196);emit32(load64(target+24)*8);}
            }else if op==10 || op==11 || op==12 {
                let kind=233;if op==11 {test_rax();kind=132;}else if op==12 {test_rax();kind=133;}
                let at=jump(kind);store64(branches+used*16,at);store64(branches+used*16+8,arg);used=used+1;
            }else if op==13 {normalize();}
            else if op==14 || op==16 {emit(72);emit(247);if op==14 {emit(216);}else {emit(208);}}
            else if op==15 {test_rax();emit(15);emit(148);emit(192);emit(72);emit(15);emit(182);emit(192);}
            pc=pc+16;
        }i=i+1;
    }
    i=0;while i<used {let at=load64(branches+i*16);patch32(at,load64(map+load64(branches+i*16+8)/2)-at-4);i=i+1;}
    resolve();return 0;
}
fn ir_native_word_io(reading) {
    // A word is framed as eight little-endian bytes. Preserve pending expression
    // operands on the stack; syscall clobbers rcx/r11, not r8/r9.
    emit(80);if reading {emit(72);emit(199);emit(4);emit(36);emit32(0);}
    emit(73);emit(137);emit(225); // r9 = rsp
    emit(65);emit(184);emit32(8); // r8 = remaining
    let loop=output_size;emit(76);emit(137);emit(206); // rsi = r9
    emit(76);emit(137);emit(194); // rdx = r8
    let number=1;if reading {number=0;}emit(191);emit32(number);emit(184);emit32(number);emit(15);emit(5);
    emit(72);emit(131);emit(248);emit(252);let retry=jump(132);patch32(retry,loop-retry-4);
    emit(72);emit(133);emit(192);let failed=jump(142);
    emit(73);emit(1);emit(193);emit(73);emit(41);emit(192);
    let more=jump(133);patch32(more,loop-more-4);emit(88);let done=jump(233);
    patch_jump(failed);emit(72);emit(131);emit(196);emit(8);immediate(-1);patch_jump(done);return 0;
}
