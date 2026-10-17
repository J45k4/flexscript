// Native Linux x86-64 ELF startup, call relocation and System V FFI.
// Entry dispatch also selects the shared word-IR and freestanding paths.
fn initialize_output() {
    if vm_mode {return 0;}
    if baremetal_target {return baremetal_initialize();}
    let i = 0;
    while i < 120 { emit(0); i = i + 1; }
    store8(output, 127); store8(output + 1, 69);
    store8(output + 2, 76); store8(output + 3, 70);
    store8(output + 4, 2); store8(output + 5, 1); store8(output + 6, 1);
    store8(output + 16, 2); store8(output + 18, 62);
    patch32(20, 1); store64(output + 24, 4194424);
    store64(output + 32, 64);
    store8(output + 52, 64); store8(output + 54, 56); store8(output + 56, 1);
    patch32(64, 1); patch32(68, 7);
    store64(output + 80, 4194304); store64(output + 88, 4194304);
    store64(output + 112, 4096);
    // Establish round-to-nearest, gradual underflow and masked FP exceptions.
    emit(104);emit32(8064);emit(15);emit(174);emit(20);emit(36);emit(72);emit(131);emit(196);emit(8);
    emit(72); emit(139); emit(4); emit(36); emit(80);
    emit(72); emit(141); emit(68); emit(36); emit(16); emit(80);
    emit(232); native_main_call=output_size; emit32(0);
    emit(72); emit(131); emit(196); emit(16);
    word_io_exit();
    emit(72); emit(137); emit(199);
    emit(184); emit32(60); emit(15); emit(5);
    return 0;
}

fn resolve() {
    lowering_validate();
    if ptx_target || sass_target || hip_target || cpu_cxx_target {vm_resolve();return 0;}
    let main_index = find(functions, function_count, "main", 4);
    if main_index < 0 { fail("missing main function"); }
    let entry = functions + main_index * 32;
    let count = load64(entry + 24);
    if count != 0 && count != 2 { fail("main must take zero or two parameters"); }
    if vm_mode {vm_resolve();return 0;}
    if baremetal_target && count != 0 {fail("bare-metal main must take zero parameters");}
    patch32(native_main_call, load64(entry + 16) - native_main_call - 4);
    let i = 0;
    while i < call_count {
        let site = calls + i * 32;
        let index = find(functions, function_count, load64(site), load64(site + 8));
        let target = 0;
        if index < 0 {
            target = ffi_resolve(load64(site),load64(site+8),load64(site+24));
            if !target { locate_name(load64(site)); if baremetal_target {fail("undefined function; dynamic FFI is unavailable on bare metal");}fail("undefined function"); }
        } else {
            let function = functions + index * 32;
            if load64(function + 24) != load64(site + 24) {
                locate_name(load64(site)); fail("wrong function argument count");
            }
            target=load64(function+16);
        }
        let at = load64(site + 16);
        if at>=0 {patch32(at, target - at - 4);}
        i = i + 1;
    }
    if ffi_dynamic { ffi_finish(load64(entry+16)); }
    if baremetal_target {baremetal_finish();}
    else {store64(output + 96, output_size);store64(output + 104, output_size);}
    return 0;
}

// FFI adapters bridge Flexscript's internal stack ABI to System V AMD64.
// Named Flexscript functions take precedence, allowing a frozen bootstrap shim.
fn ffi_argument(reg,offset) {
    emit(72); if reg>=8 { store8(output+output_size-1,76); }
    emit(139); emit(133|((reg&7)<<3)); emit32(offset); return 0;
}
fn ffi_indirect(symbol) {
    emit(255); emit(21);
    store64(ffi_fixups+ffi_fixup_count*16,output_size);
    store64(ffi_fixups+ffi_fixup_count*16+8,symbol);
    ffi_fixup_count=ffi_fixup_count+1; emit32(0); return 0;
}
fn ffi_resolve(name,size,count) {
    let kind=-1; let arity=7;
    if equal(name,size,"ffi_open",8) {kind=0;arity=1;}
    else if equal(name,size,"ffi_symbol",10) {kind=1;arity=2;}
    else if equal(name,size,"ffi_call",8) {kind=2;}
    else if equal(name,size,"ffi_call_i32",12) {kind=3;}
    else if equal(name,size,"ffi_call_u32",12) {kind=4;}
    if kind<0 {return 0;}
    if baremetal_target && kind<2 {return 0;}
    if count!=arity {locate_name(name);fail("wrong FFI argument count");}
    let cached=load64(ffi_entries+kind*8); if cached {return cached;}
    let at=output_size;store64(ffi_entries+kind*8,at);
    emit(85);emit(72);emit(137);emit(229); // preserve rbp
    if kind==0 {ffi_argument(7,16);emit(190);emit32(2);ffi_dynamic=1;}
    else if kind==1 {ffi_argument(7,24);ffi_argument(6,16);ffi_dynamic=1;}
    else {
        ffi_argument(0,64);ffi_argument(7,56);ffi_argument(6,48);
        ffi_argument(2,40);ffi_argument(1,32);ffi_argument(8,24);ffi_argument(9,16);
    }
    emit(72);emit(131);emit(228);emit(240); // and rsp,-16 before C call
    if kind<2 {ffi_indirect(kind);} else {emit(255);emit(208);}
    if kind==3 {emit(72);emit(152);} // sign extend C int
    else if kind==4 {emit(137);emit(192);} // zero extend C unsigned int
    epilogue();return at;
}
fn ffi_align() {while output_size%8 {emit(0);}return 0;}
fn ffi_tag(tag,value) {emit64(tag);emit64(value);return 0;}
fn ffi_phdr(kind,flags,offset,size,alignment) {
    emit32(kind);emit32(flags);emit64(offset);emit64(4194304+offset);
    emit64(4194304+offset);emit64(size);emit64(size);emit64(alignment);return 0;
}
fn ffi_finish(main_address) {
    // C runtime startup initializes environ, TLS and libc before calling our
    // stack-ABI main, and returns through libc for orderly library cleanup.
    let main_bridge=output_size;
    emit(85);emit(72);emit(137);emit(229);emit(87);emit(86);
    emit(232);emit32(main_address-output_size-4);
    emit(72);emit(131);emit(196);emit(16);epilogue();
    let start=output_size;store64(output+24,4194304+start);
    emit(49);emit(237);emit(73);emit(137);emit(209); // rbp=0, r9=rtld_fini
    emit(94);emit(72);emit(137);emit(226); // argc -> rsi, argv -> rdx
    emit(72);emit(131);emit(228);emit(240);emit(80);emit(84);
    emit(69);emit(49);emit(192);emit(49);emit(201);
    emit(72);emit(141);emit(61);emit32(main_bridge-output_size-4);
    ffi_indirect(2);emit(244);
    ffi_align();let got=output_size;emit64(0);emit64(0);emit64(0);
    let i=0;while i<ffi_fixup_count {
        let at=load64(ffi_fixups+i*16);let symbol=load64(ffi_fixups+i*16+8);
        patch32(at,got+symbol*8-at-4);i=i+1;
    }
    let strings=output_size;
    let names="\0dlopen\0dlsym\0__libc_start_main\0libc.so.6\0";
    i=0;while i<42 {emit(load8(names+i));i=i+1;}
    ffi_align();let symbols=output_size;i=0;while i<24 {emit(0);i=i+1;}
    i=0;while i<3 {
        let name_offset=1;if i==1 {name_offset=8;}else if i==2 {name_offset=14;}
        emit32(name_offset);emit(18);emit(0);emit(0);emit(0);emit64(0);emit64(0);i=i+1;
    }
    let hashes=output_size;emit32(1);emit32(4);emit32(1);
    emit32(0);emit32(2);emit32(3);emit32(0);
    ffi_align();let relocations=output_size;i=0;while i<3 {
        emit64(4194304+got+i*8);emit64(((i+1)<<32)|6);emit64(0);i=i+1;
    }
    let dynamic=output_size;
    ffi_tag(1,32);ffi_tag(4,4194304+hashes);ffi_tag(5,4194304+strings);ffi_tag(10,42);
    ffi_tag(6,4194304+symbols);ffi_tag(11,24);ffi_tag(7,4194304+relocations);
    ffi_tag(8,72);ffi_tag(9,24);ffi_tag(0,0);
    let interpreter=output_size;names="/lib64/ld-linux-x86-64.so.2";
    i=0;while i<=length(names) {emit(load8(names+i));i=i+1;}
    ffi_align();let headers=output_size;let total=headers+224;
    store64(output+32,headers);store8(output+56,4);
    ffi_phdr(6,4,headers,224,8);ffi_phdr(3,4,interpreter,28,1);
    ffi_phdr(1,7,0,total,4096);ffi_phdr(2,6,dynamic,160,8);
    return 0;
}
