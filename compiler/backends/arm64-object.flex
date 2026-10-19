// Position-independent ELF64 relocatable object for Android's arm64-v8a ABI.
// Text-local calls are resolved here; static addresses use linker relocations
// against the local .data section symbol, keeping the final shared library PIC.
fn a64_symbol(name,info,visibility,section,value,size) {
    emit32(name);emit(info);emit(visibility);emit(section);emit(section>>8);
    emit64(value);emit64(size);return 0;
}
fn arm64_object_finish() {
    a64_ir=output;a64_ir_size=output_size;
    a64_map=alloc(a64_ir_size/2);a64_fixups=alloc((a64_ir_size/16+1)*24);
    a64_relocations=alloc(a64_ir_size*3);a64_entries=alloc(function_count*8);
    output=alloc(output_limit);output_size=0;vm_mode=0;
    if a64_map<0 || a64_fixups<0 || a64_relocations<0 || a64_entries<0 || output<0 {fail("cannot allocate ARM64 object generation");}
    let i=0;while i<64 {emit(0);i=i+1;}
    let text_at=output_size;i=0;
    while i<function_count {a64_function(i);i=i+1;}
    let code_end=output_size;i=0;
    while i<a64_fixup_count {
        let fix=a64_fixups+i*24;let target=load64(fix+8);
        if target<0 || target>=a64_ir_size || target%16 {fail("invalid ARM64 object branch relocation");}
        a64_patch_branch(load64(fix),load64(a64_map+target/2),load64(fix+16));i=i+1;
    }
    while output_size%8 {emit(0);}
    let data_at=output_size;i=0;while i<vm_heap_used {emit(load8(vm_heap+i));i=i+1;}
    while output_size%8 {emit(0);}
    let rela_at=output_size;i=0;
    while i<a64_relocation_count {
        let relocation=a64_relocations+i*24;
        emit64(load64(relocation)-text_at);
        emit64((1<<32)|load64(relocation+8));emit64(load64(relocation+16));i=i+1;
    }
    let sym_at=output_size;
    a64_symbol(0,0,0,0,0,0);a64_symbol(0,3,0,2,0,0); // null, local .data section
    let names=alloc(function_count*8);if names<0 {fail("cannot allocate ARM64 symbol names");}
    let name_size=1;i=0;
    while i<function_count {
        let function=functions+i*32;let size=load64(function+8);
        if equal(load64(function),size,"flexscript_main",15) {fail("flexscript_main is reserved by the Android object entry");}
        if equal(load64(function),size,"main",4) {size=15;}
        store64(names+i*8,name_size);name_size=name_size+size+1;
        let start=load64(a64_entries+i*8);let end=code_end;
        if i+1<function_count {end=load64(a64_entries+(i+1)*8);}
        // Hidden definitions cannot be preempted: direct internal BLs stay local.
        a64_symbol(load64(names+i*8),18,2,1,start-text_at,end-start);i=i+1;
    }
    let str_at=output_size;emit(0);i=0;
    while i<function_count {
        let function=functions+i*32;let name=load64(function);let size=load64(function+8);
        if equal(name,size,"main",4) {name="flexscript_main";size=15;}
        let k=0;while k<size {emit(load8(name+k));k=k+1;}emit(0);i=i+1;
    }
    let shstr_at=output_size;
    let text="\0.text\0.data\0.rela.text\0.symtab\0.strtab\0.shstrtab\0.note.GNU-stack\0";
    i=0;while i<66 {emit(load8(text+i));i=i+1;}
    while output_size%8 {emit(0);}
    let sections=output_size;i=0;while i<512 {emit(0);i=i+1;}
    a64_section(sections+64,1,1,6,0,text_at,code_end-text_at,4);
    a64_section(sections+128,7,1,3,0,data_at,vm_heap_used,8);
    a64_section(sections+192,13,4,0,0,rela_at,a64_relocation_count*24,8);
    patch32(sections+192+40,4);patch32(sections+192+44,1);store64(output+sections+192+56,24);
    a64_section(sections+256,24,2,0,0,sym_at,(function_count+2)*24,8);
    patch32(sections+256+40,5);patch32(sections+256+44,2);store64(output+sections+256+56,24);
    a64_section(sections+320,32,3,0,0,str_at,name_size,1);
    a64_section(sections+384,40,3,0,0,shstr_at,66,1);
    a64_section(sections+448,50,1,0,0,0,0,1);
    patch32(0,0x464c457f);store8(output+4,2);store8(output+5,1);store8(output+6,1);
    store8(output+16,1);store8(output+18,183);patch32(20,1);
    store64(output+40,sections);store8(output+52,64);store8(output+58,64);
    store8(output+60,8);store8(output+62,6);return 0;
}
