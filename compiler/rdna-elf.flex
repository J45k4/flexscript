// Standalone ELF64 AMDHSA code-object v5 writer; no linker or template image.
global rd_sgprs=32;
fn rd_zero(n) {let i=0;while i<n {emit(0);i=i+1;}return 0;}
fn rd_align(n) {while output_size%n {emit(0);}return 0;}
fn rd_string(s) {let at=output_size;p_text(s);emit(0);return at;}
fn rd_mp_string(s) {
    let n=length(s);if n<32 {emit(0xa0+n);}else {if n>255 {fail("RDNA metadata string too long");}emit(0xd9);emit(n);}
    p_text(s);return 0;
}
fn rd_mp_int(n) {
    if n<128 {emit(n);}else if n<256 {emit(0xcc);emit(n);}else if n<65536 {emit(0xcd);emit(n>>8);emit(n);}
    else {emit(0xce);emit(n>>24);emit(n>>16);emit(n>>8);emit(n);}return 0;
}
fn rd_mp_field(name,value) {rd_mp_string(name);rd_mp_int(value);return 0;}
fn rd_metadata(registers) {
    emit(0x83);rd_mp_string("amdhsa.version");emit(0x92);emit(1);emit(2);
    rd_mp_string("amdhsa.target");rd_mp_string("amdgcn-amd-amdhsa--gfx1201");
    rd_mp_string("amdhsa.kernels");emit(0x91);emit(0x8c);
    rd_mp_string(".name");rd_mp_string("flex_kernel");rd_mp_string(".symbol");rd_mp_string("flex_kernel.kd");
    rd_mp_field(".kernarg_segment_size",344);rd_mp_field(".kernarg_segment_align",8);
    rd_mp_field(".group_segment_fixed_size",0);rd_mp_field(".private_segment_fixed_size",0);
    rd_mp_field(".sgpr_count",rd_sgprs);rd_mp_field(".vgpr_count",registers);rd_mp_field(".wavefront_size",32);
    // Match COMPUTE_PGM_RSRC1.WGP_MODE below. Occupancy queries otherwise
    // assume CU mode and undercount the resident blocks on RDNA.
    rd_mp_string(".workgroup_processor_mode");emit(0xc3);
    rd_mp_field(".max_flat_workgroup_size",1024);rd_mp_string(".args");emit(0xdc);emit(0);emit(17);
    let i=0;while i<17 {
        emit(0x83);let offset=i*8;let size=8;let kind="by_value";
        if i>=11 && i<=13 {offset=88+(i-11)*4;size=4;kind="hidden_block_count_x";if i==12 {kind="hidden_block_count_y";}else if i==13 {kind="hidden_block_count_z";}}
        else if i>=14 {offset=100+(i-14)*2;size=2;kind="hidden_group_size_x";if i==15 {kind="hidden_group_size_y";}else if i==16 {kind="hidden_group_size_z";}}
        rd_mp_field(".offset",offset);rd_mp_field(".size",size);rd_mp_string(".value_kind");rd_mp_string(kind);i=i+1;
    }return 0;
}
fn rd_symbol(at,name,info,section,address,size) {
    store64(at,name|(info<<32)|(3<<40)|(section<<48));store64(at+8,address);store64(at+16,size);return 0;
}
fn rd_program(at,kind,flags,offset,size,alignment) {
    store64(at,kind|(flags<<32));store64(at+8,offset);store64(at+16,offset);store64(at+24,offset);
    store64(at+32,size);store64(at+40,size);store64(at+48,alignment);return 0;
}
fn rd_section(at,name,kind,flags,offset,size,link,info,alignment,entsize) {
    store64(at,name|(kind<<32));store64(at+8,flags);if flags&2 {store64(at+16,offset);}
    store64(at+24,offset);store64(at+32,size);store64(at+40,link|(info<<32));store64(at+48,alignment);store64(at+56,entsize);return 0;
}
fn rd_elf(registers) {
    let code=output;let bytes=output_size;output=alloc(output_limit);output_size=0;
    if output<0 {fail("cannot allocate direct RDNA code object");}rd_zero(232);
    let note=output_size;emit32(7);let note_size=output_size;emit32(0);emit32(32);p_text("AMDGPU");rd_zero(2);
    let meta=output_size;rd_metadata(registers);let metadata_bytes=output_size-meta;
    let i=0;while i<4 {store8(output+note_size+i,metadata_bytes>>(i*8));i=i+1;}rd_align(4);let note_bytes=output_size-note;
    let names=output_size;emit(0);rd_string("flex_kernel");rd_string("flex_kernel.kd");let names_bytes=output_size-names;
    rd_align(8);let symbols=output_size;rd_zero(72);rd_align(4);let hash=output_size;
    emit32(1);emit32(3);emit32(1);emit32(0);emit32(2);emit32(0);
    rd_align(64);let descriptor=output_size;rd_zero(64);rd_align(256);let text=output_size;
    i=0;while i<bytes {emit(load8(code+i));i=i+1;}rd_align(8);let dynamic=output_size;
    emit64(5);emit64(names);emit64(10);emit64(names_bytes);emit64(6);emit64(symbols);
    emit64(11);emit64(24);emit64(4);emit64(hash);emit64(0);emit64(0);let load_bytes=output_size;
    store64(output+descriptor+8,344);store64(output+descriptor+16,text-descriptor);
    store64(output+descriptor+40,0xf0<<32);store64(output+descriptor+48,(0xe00f0000+(registers+7)/8-1)|(0x1384<<32));
    store64(output+descriptor+56,0x408);
    rd_symbol(output+symbols+24,1,18,6,text,bytes);rd_symbol(output+symbols+48,13,17,5,descriptor,64);
    let section_names=output_size;let section_offsets=alloc(11*8);emit(0);
    store64(section_offsets+8,rd_string(".note")-section_names);store64(section_offsets+16,rd_string(".dynstr")-section_names);
    store64(section_offsets+24,rd_string(".dynsym")-section_names);store64(section_offsets+32,rd_string(".hash")-section_names);
    store64(section_offsets+40,rd_string(".rodata")-section_names);store64(section_offsets+48,rd_string(".text")-section_names);
    store64(section_offsets+56,rd_string(".dynamic")-section_names);store64(section_offsets+64,rd_string(".shstrtab")-section_names);
    store64(section_offsets+72,rd_string(".strtab")-section_names);store64(section_offsets+80,rd_string(".symtab")-section_names);
    let section_name_bytes=output_size-section_names;rd_align(8);let shoff=output_size;rd_zero(11*64);
    let sections=output+shoff;
    rd_section(sections+64,load64(section_offsets+8),7,2,note,note_bytes,0,0,4,0);
    rd_section(sections+128,load64(section_offsets+16),3,2,names,names_bytes,0,0,1,0);
    rd_section(sections+192,load64(section_offsets+24),11,2,symbols,72,2,1,8,24);
    rd_section(sections+256,load64(section_offsets+32),5,2,hash,24,3,0,4,4);
    rd_section(sections+320,load64(section_offsets+40),1,2,descriptor,64,0,0,64,0);
    rd_section(sections+384,load64(section_offsets+48),1,6,text,bytes,0,0,256,0);
    rd_section(sections+448,load64(section_offsets+56),6,3,dynamic,96,2,0,8,16);
    rd_section(sections+512,load64(section_offsets+64),3,0,section_names,section_name_bytes,0,0,1,0);
    // HIP's loader also requires the conventional static symbol/string sections.
    rd_section(sections+576,load64(section_offsets+72),3,0,names,names_bytes,0,0,1,0);
    rd_section(sections+640,load64(section_offsets+80),2,0,symbols,72,9,1,8,24);
    store64(output,0x40010102464c457f);store64(output+8,4);store64(output+16,0x0000000100e00003);
    store64(output+32,64);store64(output+40,shoff);store64(output+48,0x003800400000004e);
    store64(output+56,0x0008000b00400003);
    rd_program(output+64,1,7,0,load_bytes,256);rd_program(output+120,4,4,note,note_bytes,4);rd_program(output+176,2,6,dynamic,96,8);
    return 0;
}
