// WebAssembly binary emission. The existing frontend supplies its word IR;
// each function lowers to real i64 operations and ordinary WASM calls.
// Basic blocks use a br_table dispatcher; there is no guest bytecode interpreter.
global wasm_target=0;
global w_ir=0;
global w_ir_size=0;
global w_imports=0;
global w_import_count=0;
global w_section=0;
global w_body=0;
global w_blocks=0;
global w_block_count=0;
global w_slots=0;
global w_acc=0;
global w_pc=0;
global w_depth=0;

fn wasm_initialize() {
    vm_heap=alloc(vm_heap_limit);
    if vm_heap<0 {fail("cannot allocate WebAssembly data image");}
    return 0;
}
fn w_u(value) {
    if value<0 {fail("invalid unsigned WebAssembly immediate");}
    while value>=128 {emit((value&127)|128);value=value>>7;}
    emit(value);return 0;
}
fn w_s(value) {
    let more=1;
    while more {
        let byte=value&127;value=value>>7;
        if (value==0 && !(byte&64)) || (value==-1 && (byte&64)) {more=0;}
        else {byte=byte|128;}
        emit(byte);
    }return 0;
}
fn w_bytes(data,size) {let i=0;while i<size {emit(load8(data+i));i=i+1;}return 0;}
fn w_name(text,size) {w_u(size);w_bytes(text,size);return 0;}
// Fixed-width, valid u32 LEBs reserve lengths without moving payloads.
fn w_length() {let at=output_size;let i=0;while i<4 {emit(128);i=i+1;}emit(0);return at;}
fn w_patch_length(at) {
    let value=output_size-at-5;let i=0;
    while i<4 {store8(output+at+i,(value&127)|128);value=value>>7;i=i+1;}
    store8(output+at+4,value);return 0;
}
fn w_begin(id) {emit(id);w_section=w_length();return 0;}
fn w_end() {w_patch_length(w_section);return 0;}
fn w_get(index) {emit(32);w_u(index);return 0;}
fn w_set(index) {emit(33);w_u(index);return 0;}
fn w_const(value) {emit(66);w_s(value);return 0;}
fn w_i32(value) {emit(65);w_s(value);return 0;}
fn w_bool() {emit(80);emit(69);return 0;}
fn w_mem(op) {emit(op);w_u(0);w_u(0);return 0;}
fn w_address(index) {
    // A word-sized pointer must not alias memory by truncating its high bits.
    w_get(index);w_const(4294967295);emit(86);
    w_get(index);w_const(16);emit(84);emit(114);
    emit(4);emit(64);emit(0);emit(11);
    w_get(index);emit(167);return 0;
}
fn w_arity(op,arg) {
    if op==8 {return load64(functions+arg*32+24);}
    if op!=17 {return 0;}
    if arg==1 || arg==2 || arg==5 || arg==7 {return 1;}
    if arg==3 || arg==4 || arg==8 {return 2;}
    if arg==6 || (arg>=9 && arg<=11) {return 7;}
    fail("unsupported WebAssembly builtin");return 0;
}
fn w_import_name(kind) {
    if kind==6 {return "syscall";}if kind==7 {return "ffi_open";}
    if kind==8 {return "ffi_symbol";}if kind==9 {return "ffi_call";}
    if kind==10 {return "ffi_call_i32";}return "ffi_call_u32";
}
fn w_binary(op,left) {
    if op==47 || op==37 {
        // WASM rem_s(MIN,-1) is zero; Flexscript traps for both / and %.
        w_get(left);w_const(-9223372036854775807-1);emit(81);
        w_get(w_acc);w_const(-1);emit(81);emit(113);
        emit(4);emit(64);emit(0);emit(11);
    }
    w_get(left);w_get(w_acc);
    let code=0;let comparison=0;
    if op==43 {code=124;}else if op==45 {code=125;}else if op==42 {code=126;}
    else if op==47 {code=127;}else if op==37 {code=129;}
    else if op==38 {code=131;}else if op==124 {code=132;}else if op==94 {code=133;}
    else if op==265 {code=134;}else if op==266 {code=135;}
    else {
        comparison=1;
        if op==259 {code=81;}else if op==260 {code=82;}
        else if op==60 {code=83;}else if op==62 {code=85;}
        else if op==261 {code=87;}else if op==262 {code=89;}
        else {fail("invalid WebAssembly binary operation");}
    }
    emit(code);if comparison {emit(173);}w_set(w_acc);return 0;
}
fn w_builtin(kind,first) {
    if kind==1 || kind==2 {
        w_address(first);let op=49;if kind==2 {op=41;}w_mem(op);w_set(w_acc);
    }else if kind==3 || kind==4 {
        w_address(first);w_get(first+1);let op=60;if kind==4 {op=55;}w_mem(op);
        w_get(first+1);w_set(w_acc);
    }else {
        let count=w_arity(17,kind);let i=0;
        while i<count {w_get(first+i);i=i+1;}
        emit(16);
        if kind==5 {w_u(w_import_count+function_count);}
        else {w_u(load64(w_imports+kind*8));}
        if kind==10 {emit(167);emit(172);}
        else if kind==11 {emit(167);emit(173);}
        w_set(w_acc);
    }return 0;
}
fn w_block_of(pc) {return load64(w_blocks+(pc/16)*8);}
fn w_dispatch(target,label) {w_i32(target);w_set(w_pc);emit(12);w_u(label);return 0;}
fn w_function(index) {
    let entry=functions+index*32;let start=load64(entry+16)+16;let end=w_ir_size;
    if index+1<function_count {end=load64(functions+(index+1)*32+16);}
    w_slots=load64(w_ir+start-8);w_acc=w_slots;w_depth=0;
    // Mark control-flow boundaries. Every instruction still lowers directly.
    let pc=start;while pc<end {store64(w_blocks+(pc/16)*8,-1);pc=pc+16;}
    store64(w_blocks+(start/16)*8,0);
    pc=start;let maximum=0;
    while pc<end {
        let op=load64(w_ir+pc);let arg=load64(w_ir+pc+8);
        if op==2 {w_depth=w_depth+1;if w_depth>maximum {maximum=w_depth;}}
        else if op==7 {w_depth=w_depth-1;}
        else if op==8 || op==17 {w_depth=w_depth-w_arity(op,arg);}
        if w_depth<0 {fail("invalid WebAssembly expression stack");}
        if op==10 || op==11 || op==12 {
            if arg<start || arg>=end || arg%16 {fail("invalid WebAssembly jump");}
            store64(w_blocks+(arg/16)*8,0);
        }
        if (op==9 || op==10 || op==11 || op==12) && pc+16<end {store64(w_blocks+((pc+16)/16)*8,0);}
        pc=pc+16;
    }
    if w_depth {fail("unbalanced WebAssembly expression stack");}
    w_block_count=0;pc=start;
    while pc<end {
        if w_block_of(pc)==0 {store64(w_blocks+(pc/16)*8,w_block_count);w_block_count=w_block_count+1;}
        pc=pc+16;
    }
    w_body=w_length();
    // Source locals and expression temporaries are i64; dispatch PC is i32.
    w_u(2);w_u(w_slots-load64(entry+24)+maximum+1);emit(126);w_u(1);emit(127);
    w_pc=w_slots+maximum+1;
    emit(2);emit(64);emit(3);emit(64);
    let i=0;while i<w_block_count {emit(2);emit(64);i=i+1;}
    w_get(w_pc);emit(14);w_u(w_block_count);
    i=0;while i<w_block_count {w_u(i);i=i+1;}w_u(w_block_count+1);
    w_depth=0;let block=-1;pc=start;
    while pc<end {
        if w_block_of(pc)>=0 {emit(11);block=block+1;}
        let op=load64(w_ir+pc);let arg=load64(w_ir+pc+8);
        let label=w_block_count-block-1;
        if op==1 {w_const(arg);w_set(w_acc);}
        else if op==2 {w_get(w_acc);w_set(w_slots+1+w_depth);w_depth=w_depth+1;}
        else if op==3 {w_get(arg);w_set(w_acc);}
        else if op==4 {w_get(w_acc);w_set(arg);}
        else if op==5 {w_i32(arg);w_mem(41);w_set(w_acc);}
        else if op==6 {w_i32(arg);w_get(w_acc);w_mem(55);}
        else if op==7 {w_depth=w_depth-1;w_binary(arg,w_slots+1+w_depth);}
        else if op==8 {
            let arity=w_arity(op,arg);w_depth=w_depth-arity;i=0;
            while i<arity {w_get(w_slots+1+w_depth+i);i=i+1;}
            emit(16);w_u(w_import_count+arg);w_set(w_acc);
        }else if op==9 {w_get(w_acc);emit(15);}
        else if op==10 {w_dispatch(w_block_of(arg),label);}
        else if op==11 || op==12 {
            w_i32(w_block_of(arg));w_i32(w_block_of(pc+16));w_get(w_acc);
            if op==11 {emit(80);}else {w_bool();}
            emit(27);w_set(w_pc);emit(12);w_u(label);
        }else if op==13 {w_get(w_acc);w_bool();emit(173);w_set(w_acc);}
        else if op==14 {w_const(0);w_get(w_acc);emit(125);w_set(w_acc);}
        else if op==15 {w_get(w_acc);emit(80);emit(173);w_set(w_acc);}
        else if op==16 {w_get(w_acc);w_const(-1);emit(133);w_set(w_acc);}
        else if op==17 {let arity=w_arity(op,arg);w_depth=w_depth-arity;w_builtin(arg,w_slots+1+w_depth);}
        else {fail("invalid WebAssembly instruction");}
        if op!=9 && op!=10 && op!=11 && op!=12 && pc+16<end && w_block_of(pc+16)>=0 {
            w_dispatch(w_block_of(pc+16),label);
        }
        pc=pc+16;
    }
    emit(11);emit(11);emit(0);emit(11);w_patch_length(w_body);return 0;
}
fn w_allocator() {
    w_body=w_length();w_u(1);w_u(2);emit(126); // size, base, end
    w_get(0);emit(80);emit(4);emit(64);w_const(-22);emit(15);emit(11);
    w_get(0);w_const(1073741824);emit(86);
    emit(4);emit(64);w_const(-12);emit(15);emit(11);
    emit(35);w_u(0);w_set(1);
    w_get(1);w_get(0);w_const(7);emit(124);w_const(-8);emit(131);emit(124);w_set(2);
    w_get(2);w_const(1073741824);emit(86);
    emit(4);emit(64);w_const(-12);emit(15);emit(11);
    w_get(2);emit(63);emit(0);emit(173);w_const(65536);emit(126);emit(86);
    emit(4);emit(64);
    w_get(2);w_const(65535);emit(124);w_const(16);emit(136);emit(167);
    emit(63);emit(0);emit(107);emit(64);emit(0);w_i32(-1);emit(70);
    emit(4);emit(64);w_const(-12);emit(15);emit(11);emit(11);
    w_get(2);emit(36);w_u(0);w_get(1);emit(11);
    w_patch_length(w_body);return 0;
}
fn wasm_finish() {
    w_ir=output;w_ir_size=output_size;output=alloc(67108864);output_size=0;
    w_imports=alloc(12*8);w_blocks=alloc((w_ir_size/16+1)*8);
    if output<0 || w_imports<0 || w_blocks<0 {fail("cannot allocate WebAssembly output");}
    let i=0;while i<12 {store64(w_imports+i*8,-1);i=i+1;}
    i=0;let max_arity=1;
    while i<function_count {let n=load64(functions+i*32+24);if n>max_arity {max_arity=n;}i=i+1;}
    i=0;while i<w_ir_size {
        if load64(w_ir+i)==17 {
            let kind=load64(w_ir+i+8);
            if kind>=6 {
                if load64(w_imports+kind*8)<0 {store64(w_imports+kind*8,w_import_count);w_import_count=w_import_count+1;}
                let arity=w_arity(17,kind);if arity>max_arity {max_arity=arity;}
            }
        }i=i+16;
    }
    emit32(0x6d736100);emit32(1);
    w_begin(1);w_u(max_arity+1);i=0;
    while i<=max_arity {emit(96);w_u(i);let k=0;while k<i {emit(126);k=k+1;}w_u(1);emit(126);i=i+1;}w_end();
    if w_import_count {
        w_begin(2);w_u(w_import_count);
        // Preserve the function indices assigned by the scan, not kind order.
        i=0;while i<w_import_count {
            let kind=6;while load64(w_imports+kind*8)!=i {kind=kind+1;}
            w_name("flex",4);let name=w_import_name(kind);w_name(name,length(name));emit(0);w_u(w_arity(17,kind));i=i+1;
        }w_end();
    }
    w_begin(3);w_u(function_count+1);i=0;
    while i<function_count {w_u(load64(functions+i*32+24));i=i+1;}w_u(1);w_end();
    w_begin(5);w_u(1);w_u(1);w_u((vm_heap_used+65535)/65536);w_u(16384);w_end();
    w_begin(6);w_u(1);emit(126);emit(1);w_const(vm_heap_used);emit(11);w_end();
    w_begin(7);w_u(function_count+2);
    w_name("memory",6);emit(2);w_u(0);
    w_name("__flex_alloc",12);emit(0);w_u(w_import_count+function_count);
    i=0;while i<function_count {
        let entry=functions+i*32;
        if equal(load64(entry),load64(entry+8),"memory",6) || equal(load64(entry),load64(entry+8),"__flex_alloc",12) {
            if !frontend_language {locate_name(load64(entry));}fail("function name conflicts with a WebAssembly runtime export");
        }
        w_name(load64(entry),load64(entry+8));emit(0);w_u(w_import_count+i);i=i+1;
    }w_end();
    w_begin(10);w_u(function_count+1);i=0;while i<function_count {w_function(i);i=i+1;}w_allocator();w_end();
    w_begin(11);w_u(1);w_u(0);w_i32(16);emit(11);w_u(vm_heap_used-16);w_bytes(vm_heap+16,vm_heap_used-16);w_end();
    return 0;
}
