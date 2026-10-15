import "lib/esp32-elf.flex";
// Link fixed native Flexscript code with explicit Xtensa C objects/archives.
// GNU ld supplies vendor relocation/archive support; Flexscript code is unchanged.
fn el_alias(a,b) {
    if !a || !b {return 0;}if h_equal(h_absolute(a),h_absolute(b)) {return 1;}
    let x=h_take(144);let y=h_take(144);if syscall(4,a,x,0,0,0,0)==0 && syscall(4,b,y,0,0,0,0)==0 {return load64(x)==load64(y) && load64(x+8)==load64(y+8);}return 0;
}
fn b_flag(argc,argv,name) {let i=1;while i<argc {if h_equal(load64(argv+i*8),name) {return 1;}i=i+1;}return 0;}
fn main(argc,argv) {
    h_environment(argc,argv);let input=b_option(argc,argv,"--firmware",0);let output=b_option(argc,argv,"--output",0);let linker=b_option(argc,argv,"--ld","xtensa-esp32-elf-ld");
    h_assert(input && output,"requires --firmware linkable.elf --output linked.elf [--object file.o] [--archive file.a] [--rom file.ld]");h_assert(!h_equal(h_absolute(input),h_absolute(output)),"firmware and output must differ");
    let image=b_option(argc,argv,"--image",0);let map=b_option(argc,argv,"--map",0);
    h_assert(!el_alias(input,output) && !el_alias(input,image) && !el_alias(input,map) && !el_alias(output,image) && !el_alias(output,map) && !el_alias(image,map),"link outputs alias another input/output");
    let bytes=h_read(input);let elf=ee_open(bytes,h_file_size);let profile=ee_profile(elf);let chip=ee_u32(profile+4);let code_base=0x40380000;let data_base=0x3fcb0000;let data_limit=data_base+65536;
    if !chip {code_base=0x40080000;data_base=0x3ffb0000;data_limit=0x3ffb8000;if ee_u32(profile+12)==0x3ffc0000 {h_assert(ee_u32(profile+16)==0x3ffe8000 && ee_u32(profile+24)==0x3ffb6400 && ee_u32(profile+28)==0x3ffb8000,"invalid Bluetooth memory profile");data_base=0x3ffc0000;data_limit=0x3ffc8000;}}
    h_assert(ee_u32(profile+8)==code_base && ee_u32(profile+12)==data_base,"firmware has unexpected memory layout");
    let xip=b_flag(argc,argv,"--xip");h_assert(xip || !ee_section(elf,".flex.irom"),"flash firmware requires --xip");h_assert(!xip || (!chip && ee_u32(profile+16)==0x3ffe8000),"--xip requires --target esp32-radio-elf");
    let imports=ee_section(elf,".flex.imports");let strings=ee_section(elf,".strtab");let object=ee_object(elf);let object_size=h_file_size;
    let work=h_temp();let obj=h_join(work,"flex-runtime.o");let script=h_join(work,"memory.ld");let linked=h_join(work,"linked.elf");h_save_bytes(obj,object,object_size,420);
    let regions="PHDRS { iram PT_LOAD FLAGS(5); dram PT_LOAD FLAGS(6);";if xip {regions=h_cat(regions," irom PT_LOAD FLAGS(5); drom PT_LOAD FLAGS(4);");}regions=h_cat(regions," }\nSECTIONS {\n");
    let text=h_cat3("ENTRY(flex_firmware_entry)\nflex_firmware_entry = ",h_int(ee_u32(bytes+24)),h_cat(";\n",regions));
    text=h_cat(text,h_cat3(".text ",h_int(code_base)," : { KEEP(\""));text=h_cat(text,h_cat(obj,"\"(.text)) . = ALIGN(16); "));
    if xip {text=h_cat(text,"*(.iram1 .iram1.* .phyiram .phyiram.*) ");}else {text=h_cat(text,"*(.literal .literal.* .text .text.* .iram1 .iram1.* .phyiram .phyiram.*) ");}text=h_cat(text,". = ALIGN(4); } :iram\n");
    text=h_cat(text,h_cat3("ASSERT(. <= ",h_int(code_base+131072),", \"vendor code exceeds available IRAM\")\n.data "));text=h_cat(text,h_cat3(h_int(data_base)," : { KEEP(\"",obj));text=h_cat(text,"\"(.data)) . = ALIGN(16); ");if !xip {text=h_cat(text,"*(.rodata .rodata.* .rodata_wlog_*) ");}text=h_cat(text,"*(.data .data.* .sdata .sdata.* .dram0 .dram0.* .dram1 .dram1.*) _bss_start = .; *(.bss .bss.* .sbss .sbss.*) *(COMMON) _bss_end = .; . = ALIGN(4); } :dram\n");
    text=h_cat(text,h_cat3("ASSERT(. <= ",h_int(data_limit),", \"vendor data overlaps reserved SRAM\")\n"));
    if xip {text=h_cat(text,".irom 0x400d0000 : { KEEP(*(.flex.irom)) *(.literal .literal.* .text .text.*) . = ALIGN(4); } :irom\n.drom 0x3f400000 : { *(.rodata .rodata.* .rodata_wlog_*) . = ALIGN(4); } :drom\n_flex_irom_flash = 0x30000;\n_flex_irom_pages = (SIZEOF(.irom) + 65535) / 65536;\n_flex_drom_flash = _flex_irom_flash + _flex_irom_pages * 65536;\n_flex_drom_pages = (SIZEOF(.drom) + 65535) / 65536;\nASSERT(_flex_drom_flash + _flex_drom_pages * 65536 <= 0x400000, \"XIP image exceeds 4 MiB flash\")\n.flex.xip 0 : { LONG(_flex_irom_flash); LONG(_flex_irom_pages); LONG(_flex_drom_flash); LONG(_flex_drom_pages); } :NONE\n");}
    text=h_cat(text,".flex.info 0 : { KEEP(\"");text=h_cat(text,h_cat(obj,"\"(.flex.info)) } :NONE\n/DISCARD/ : { *(.flex.imports .comment .xtensa.info .xt.lit .xt.prop .eh_frame .eh_frame.*) }\n}\n"));h_save(script,text);
    let args=h_args(h_executable(linker),"--no-relax","--gc-sections","-T",script,obj);let i=1;let inputs=0;
    while i<argc {let arg=load64(argv+i*8);if h_equal(arg,"--object") || h_equal(arg,"--archive") || h_equal(arg,"--rom") {i=i+1;h_assert(i<argc,"link input needs a path");let path=h_absolute(load64(argv+i*8));h_assert(h_exists(path),h_cat("missing link input: ",path));h_assert(!el_alias(path,output) && !el_alias(path,image) && !el_alias(path,map),"link output aliases an object/archive/ROM input");if h_equal(arg,"--rom") {h_add(args,"-T");}h_add(args,path);inputs=inputs+1;}i=i+1;}
    h_assert(inputs>0,"provide vendor archives/objects or a ROM symbol script");
    // Group archives so cyclic dependencies are resolved independent of order.
    // Inputs above are already individual arguments; place all in a rescan group.
    let grouped=h_args(h_at(args,0),"--start-group",0,0,0,0);i=1;while i<h_count(args) {h_add(grouped,h_at(args,i));i=i+1;}
    h_add(grouped,"--end-group");h_add(grouped,h_cat("-Map=",h_join(work,"linked.map")));h_add(grouped,"-o");h_add(grouped,linked);h_print(1,h_out(h_ok(grouped)));
    let result=h_read(linked);let result_size=h_file_size;let final=ee_open(result,result_size);let final_profile=ee_profile(final);h_assert(ee_u32(final_profile+4)==chip,"linked chip ID changed");
    let loaded=0;i=0;while i<load64(final+56) {let ph=result+load64(final+48)+i*32;if ee_u32(ph)==1 && ee_u32(ph+20) {let base=ee_u32(ph+8);let mem=ee_u32(ph+20);let n=ee_u32(ph+16);h_assert(n<=mem && ee_range(result_size,ee_u32(ph+4),n),"invalid linked load segment");let valid=base>=code_base && mem<=code_base+131072-base && base<=code_base+131072;if !valid {valid=base>=data_base && base<=data_limit && mem<=data_limit-base;}if xip && !valid {valid=(base==0x400d0000 || base==0x3f400000) && mem<=0x300000;}h_assert(valid,"linked segment outside permitted memory");loaded=loaded+1;}i=i+1;}
    h_assert(loaded>=2,"linked image lost firmware load segments");h_assert(ee_u32(result+24)==ee_u32(bytes+24),"linked entry point changed");
    let rom=0;let rom_size=0;if image {h_assert(!h_equal(h_absolute(image),h_absolute(input)) && !h_equal(h_absolute(image),h_absolute(output)),"image output aliases ELF path");rom=ee_rom_image(final);if xip {rom=ee_xip_image(final,rom,h_file_size);}rom_size=h_file_size;}
    h_save_bytes(output,result,result_size,420);if image {h_save_bytes(image,rom,rom_size,420);}if map {h_save(map,h_read(h_join(work,"linked.map")));}h_print(1,h_cat3("Linked ESP32 firmware: ",output,"\n"));h_remove(work);return 0;
}
