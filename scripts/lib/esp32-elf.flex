import "build.flex";
// Checked ELF32 Xtensa reader used by the vendor linker tooling.
fn ee_u16(p) {return load8(p)|(load8(p+1)<<8);}
fn ee_u32(p) {return load8(p)|(load8(p+1)<<8)|(load8(p+2)<<16)|(load8(p+3)<<24);}
fn ee_w16(p,n) {store8(p,n);store8(p+1,n>>8);return 0;}
fn ee_w32(p,n) {let i=0;while i<4 {store8(p+i,n>>(i*8));i=i+1;}return 0;}
fn ee_range(size,offset,n) {return offset>=0 && n>=0 && offset<=size && n<=size-offset;}
fn ee_string(base,size,offset) {h_assert(offset>=0 && offset<size,"ELF string offset out of range");let i=offset;while i<size && load8(base+i) {i=i+1;}h_assert(i<size,"unterminated ELF string");return base+offset;}
fn ee_open(bytes,size) {
    h_assert(size>=52 && ee_u32(bytes)==0x464c457f && load8(bytes+4)==1 && load8(bytes+5)==1 && load8(bytes+6)==1 && ee_u16(bytes+18)==94 && ee_u32(bytes+20)==1 && ee_u16(bytes+40)==52,"requires ELF32 little-endian Xtensa");
    let sh=ee_u32(bytes+32);let ns=ee_u16(bytes+48);let strings=ee_u16(bytes+50);let ph=ee_u32(bytes+28);let np=ee_u16(bytes+44);
    h_assert(ee_u16(bytes+46)==40 && ns>0 && strings<ns && ee_range(size,sh,ns*40),"invalid ELF section table");
    h_assert(!np || (ee_u16(bytes+42)==32 && ee_range(size,ph,np*32)),"invalid ELF program table");
    let names=bytes+sh+strings*40;let offset=ee_u32(names+16);let length=ee_u32(names+20);h_assert(ee_u32(names+4)==3 && ee_range(size,offset,length),"invalid ELF section names");
    let result=h_take(64);store64(result,bytes);store64(result+8,size);store64(result+16,sh);store64(result+24,ns);store64(result+32,bytes+offset);store64(result+40,length);store64(result+48,ph);store64(result+56,np);
    let i=0;while i<ns {let item=bytes+sh+i*40;ee_string(bytes+offset,length,ee_u32(item));if ee_u32(item+4)!=8 {h_assert(ee_range(size,ee_u32(item+16),ee_u32(item+20)),"ELF section out of range");}i=i+1;}return result;
}
fn ee_section(elf,name) {let i=0;let bytes=load64(elf);while i<load64(elf+24) {let item=bytes+load64(elf+16)+i*40;if h_equal(ee_string(load64(elf+32),load64(elf+40),ee_u32(item)),name) {return item;}i=i+1;}return 0;}
fn ee_payload(elf,section) {h_assert(section,"missing required ELF section");return load64(elf)+ee_u32(section+16);}
fn ee_profile(elf) {let section=ee_section(elf,".flex.info");h_assert(section && ee_u32(section+20)==32,"missing Flexscript firmware profile");let p=ee_payload(elf,section);h_assert(ee_u32(p)==1 && (ee_u32(p+4)==0 || ee_u32(p+4)==9),"unsupported Flexscript firmware profile");return p;}
// The S3 SDK layout trades static/native heap space for IRAM and SDK stacks.
// IRAM aliases DRAM at -0x6f0000; never raise a size bound in isolation.
fn ee_s3_sdk(p) {
    if ee_u32(p+4)!=9 || ee_u32(p+12)!=0x3fcc0000 {return 0;}
    h_assert(ee_u32(p+8)==0x40380000 && ee_u32(p+16)==0x3fcd0000 && ee_u32(p+20)==0x3fcd8000 && ee_u32(p+24)==0x3fcc4000 && ee_u32(p+28)==0x3fcc6000,"invalid ESP32-S3 SDK memory profile");return 1;
}
fn ee_s3_xip(p) {
    if ee_u32(p+4)!=9 || ee_u32(p+12)!=0x3fca8000 {return 0;}
    h_assert(ee_u32(p+8)==0x40380000 && ee_u32(p+16)==0x3fcd0000 && ee_u32(p+20)==0x3fcd8000 && ee_u32(p+24)==0x3fcb0000 && ee_u32(p+28)==0x3fcb2000,"invalid ESP32-S3 cached memory profile");return 1;
}
fn ee_irom_base(p) {if ee_u32(p+4)==9 {return 0x42000000;}return 0x400d0000;}
fn ee_drom_base(p) {if ee_u32(p+4)==9 {return 0x3c400000;}return 0x3f400000;}
fn ee_flash_offset(p) {if ee_u32(p+4)==9 {return 0;}return 4096;}
fn ee_code_capacity(p) {if ee_s3_xip(p) {return 98304;}if ee_s3_sdk(p) {return 196608;}return 131072;}
fn ee_data_capacity(p) {if ee_s3_xip(p) {return 32768;}if ee_s3_sdk(p) {return 16384;}return 65536;}
fn ee_symbol_name(elf,table,symbol) {let index=ee_u32(table+24);h_assert(index<load64(elf+24),"invalid ELF symbol string table");let s=load64(elf)+load64(elf+16)+index*40;h_assert(ee_u32(s+4)==3,"ELF symbols require a string table");return ee_string(ee_payload(elf,s),ee_u32(s+20),ee_u32(symbol));}
fn ee_find_symbol(elf,name) {let table=ee_section(elf,".symtab");h_assert(table && ee_u32(table+36)==16 && !(ee_u32(table+20)%16),"invalid ELF symbol table");let bytes=ee_payload(elf,table);let i=0;while i<ee_u32(table+20)/16 {if h_equal(ee_symbol_name(elf,table,bytes+i*16),name) {return i;}i=i+1;}return -1;}
fn ee_valid_symbol(name) {let i=0;while load8(name+i) {let c=load8(name+i);if !((c>=65 && c<=90) || (c>=97 && c<=122) || c==95 || (i && c>=48 && c<=57)) {return 0;}i=i+1;if i>128 {return 0;}}return i>0;}
fn ee_object(elf) {
    // Fixed-address machine code becomes ET_REL; import slots use R_XTENSA_32.
    let text=ee_section(elf,".text");let data=ee_section(elf,".data");let imports=ee_section(elf,".flex.imports");let info=ee_section(elf,".flex.info");let symbols=ee_section(elf,".symtab");let strings=ee_section(elf,".strtab");
    let profile=ee_profile(elf);h_assert(ee_u16(load64(elf)+16)==2 && text && data && imports && symbols && strings,"requires a Flexscript linkable ELF executable");
    h_assert(ee_u32(text+12)==ee_u32(profile+8) && ee_u32(data+12)==ee_u32(profile+12),"firmware load profile mismatch");
    h_assert(ee_u32(text+20)>1024 && ee_u32(text+20)<=ee_code_capacity(profile) && ee_u32(data+20)>=24 && ee_u32(data+20)<=ee_data_capacity(profile) && !(ee_u32(imports+20)%8),"invalid firmware region sizes");
    h_assert(ee_u32(symbols+36)==16 && !(ee_u32(symbols+20)%16),"invalid firmware symbols");
    let flash=ee_section(elf,".flex.irom");let count_sections=9;if flash {count_sections=10;}let sections=h_args(text,data,imports,info,symbols,strings);let offsets=h_take(count_sections*8);let at=52;let i=1;
    while i<=6 {at=(at+3)&~3;store64(offsets+i*8,at);at=at+ee_u32(h_at(sections,i-1)+20);i=i+1;}
    let names=".text,.data,.flex.imports,.flex.info,.symtab,.strtab,.shstrtab,.rela.data,";if flash {names=".text,.data,.flex.imports,.flex.info,.symtab,.strtab,.shstrtab,.flex.irom,.rela.data,";}let names_size=h_len(names)+1;store64(offsets+56,at);at=at+names_size;at=(at+3)&~3;if flash {store64(offsets+64,at);at=at+ee_u32(flash+20);at=(at+3)&~3;}let relindex=count_sections-1;store64(offsets+relindex*8,at);
    let count=ee_u32(imports+20)/8;let relsize=count*12;at=at+relsize;let shoff=at;let size=shoff+count_sections*40;let out=h_take(size);
    h_copy(out,load64(elf),52);ee_w16(out+16,1);ee_w32(out+24,0);ee_w32(out+28,0);ee_w16(out+42,0);ee_w16(out+44,0);ee_w32(out+32,shoff);ee_w16(out+48,count_sections);ee_w16(out+50,7);
    i=1;while i<=6 {let src=h_at(sections,i-1);let offset=load64(offsets+i*8);h_copy(out+offset,ee_payload(elf,src),ee_u32(src+20));h_copy(out+shoff+i*40,src,40);ee_w32(out+shoff+i*40+12,0);ee_w32(out+shoff+i*40+16,offset);i=i+1;}
    // ELF symbols become section-relative, while generated instructions stay fixed.
    let sym=out+load64(offsets+40);i=1;while i<ee_u32(symbols+20)/16 {let s=sym+i*16;let section=ee_u16(s+14);if section {h_assert(section==1 || section==2 || (flash && section==8),"unsupported firmware symbol section");let region=text;if section==2 {region=data;}if section==8 {region=flash;}let value=ee_u32(s+4);let base=ee_u32(region+12);h_assert(value>=base && value-base<=ee_u32(region+20) && ee_u32(s+8)<=ee_u32(region+20)-(value-base),"firmware symbol outside region");ee_w32(s+4,value-base);}i=i+1;}
    let name_base=out+load64(offsets+56);store8(name_base,0);i=0;while i<names_size-1 {let c=load8(names+i);if c==44 {c=0;}store8(name_base+1+i,c);i=i+1;}
    let sh=out+shoff+7*40;ee_w32(sh,54);ee_w32(sh+4,3);ee_w32(sh+16,load64(offsets+56));ee_w32(sh+20,names_size);ee_w32(sh+32,1);
    if flash {let f=out+shoff+8*40;h_copy(f,flash,40);ee_w32(f,64);ee_w32(f+12,0);ee_w32(f+16,load64(offsets+64));h_copy(out+load64(offsets+64),ee_payload(elf,flash),ee_u32(flash+20));}
    let rel=out+load64(offsets+relindex*8);let inp=ee_payload(elf,imports);let pool=ee_payload(elf,strings);let data_base=ee_u32(data+12);i=0;
    while i<count {let name=ee_string(pool,ee_u32(strings+20),ee_u32(inp+i*8));h_assert(ee_valid_symbol(name),"invalid external symbol");let slot=ee_u32(inp+i*8+4);h_assert(slot>=data_base+24 && slot-data_base<=ee_u32(data+20)-8 && !(slot&7),"invalid import pointer slot");let index=ee_find_symbol(elf,name);h_assert(index>0 && ee_u16(ee_payload(elf,symbols)+index*16+14)==0,"import must reference an undefined symbol");ee_w32(rel+i*12,slot-data_base);ee_w32(rel+i*12+4,(index<<8)|1);ee_w32(rel+i*12+8,0);i=i+1;}
    sh=out+shoff+relindex*40;let relname=64;if flash {relname=75;}ee_w32(sh,relname);ee_w32(sh+4,4);ee_w32(sh+16,load64(offsets+relindex*8));ee_w32(sh+20,relsize);ee_w32(sh+24,5);ee_w32(sh+28,2);ee_w32(sh+32,4);ee_w32(sh+36,12);
    // Header names for the retained first six sections keep their original offsets.
    h_file_size=size;return out;
}
fn ee_nibble(c) {if c>=48 && c<=57 {return c-48;}if c>=97 && c<=102 {return c-87;}h_assert(0,"invalid digest hexadecimal");return 0;}
fn ee_rom_image(elf) {
    let profile=ee_profile(elf);let code_base=ee_u32(profile+8);let data_base=ee_u32(profile+12);let chip=ee_u32(profile+4);let bytes=load64(elf);let size=load64(elf+8);let entry=ee_u32(bytes+24);
    h_assert(entry>=code_base+1024 && entry<code_base+ee_code_capacity(profile),"invalid firmware entry");let n=0;let total=24;let i=0;
    while i<load64(elf+56) {let ph=bytes+load64(elf+48)+i*32;if ee_u32(ph)==1 && ee_u32(ph+20) && ee_u32(ph+8)!=ee_irom_base(profile) && ee_u32(ph+8)!=ee_drom_base(profile) {let base=ee_u32(ph+8);let memory=ee_u32(ph+20);let file=ee_u32(ph+16);h_assert(memory>0 && file<=memory && ee_range(size,ee_u32(ph+4),file) && !(base&3),"invalid firmware load segment");
        let valid=base>=code_base && base<code_base+ee_code_capacity(profile) && memory<=code_base+ee_code_capacity(profile)-base;if !valid {valid=base>=data_base && base<data_base+ee_data_capacity(profile) && memory<=data_base+ee_data_capacity(profile)-base;}h_assert(valid,"ROM image requires bounded internal SRAM segments");n=n+1;total=total+8+((memory+3)&~3);}i=i+1;}
    h_assert(n>=2 && n<=16,"unsupported ROM segment count");let output_size=((total+16)/16)*16+32;let out=h_take(output_size);let j=0;while j<output_size {store8(out+j,0);j=j+1;}
    store8(out,233);store8(out+1,n);store8(out+2,2);store8(out+3,32);ee_w32(out+4,entry);store8(out+8,238);ee_w16(out+12,chip);store8(out+17,255);store8(out+18,255);store8(out+23,1);
    let at=24;let checksum=239;i=0;while i<load64(elf+56) {let ph=bytes+load64(elf+48)+i*32;if ee_u32(ph)==1 && ee_u32(ph+20) && ee_u32(ph+8)!=ee_irom_base(profile) && ee_u32(ph+8)!=ee_drom_base(profile) {let memory=(ee_u32(ph+20)+3)&~3;let file=ee_u32(ph+16);ee_w32(out+at,ee_u32(ph+8));ee_w32(out+at+4,memory);at=at+8;h_copy(out+at,bytes+ee_u32(ph+4),file);j=0;while j<memory {checksum=checksum^load8(out+at+j);j=j+1;}at=at+memory;}i=i+1;}
    while at%16!=15 {at=at+1;}store8(out+at,checksum);at=at+1;let digest=h_sha_bytes(out,at);i=0;while i<32 {store8(out+at+i,(ee_nibble(load8(digest+i*2))<<4)|ee_nibble(load8(digest+i*2+1)));i=i+1;}h_assert(at+32==output_size,"internal ROM image layout mismatch");h_file_size=output_size;return out;
}

// A ROM-loadable SRAM image followed by 64 KiB aligned cache mappings.
// The primary image's SHA covers its RAM payload; appended XIP bytes are not
// authenticated by the ROM. Secure boot/signing is outside this image format.
fn ee_xip_image(elf,rom,rom_size) {
    let profile=ee_profile(elf);let flash_offset=ee_flash_offset(profile);let section=ee_section(elf,".flex.xip");h_assert(section && ee_u32(section+20)==16,"missing XIP layout");let layout=ee_payload(elf,section);let code=ee_section(elf,".irom");let data=ee_section(elf,".drom");h_assert(code,"missing flash code section");let data_size=0;if data {data_size=ee_u32(data+20);}
    // Orphan allocated sections can extend a PT_LOAD beyond its named section.
    // Never silently emit only a prefix and leave linked constants as 0xff.
    let si=0;while si<load64(elf+24) {let sh=load64(elf)+load64(elf+16)+si*40;let address=ee_u32(sh+12);let size=ee_u32(sh+20);
        if (ee_u32(sh+8)&2) && size {
            let region=0;let cached=0;if address>=ee_irom_base(profile) && address<ee_irom_base(profile)+0x300000 {region=code;cached=1;}else if address>=ee_drom_base(profile) && address<ee_drom_base(profile)+0x300000 {region=data;cached=1;}
            if cached {h_assert(region,"cached allocated section has no emitted image section");let base=ee_u32(region+12);let length=ee_u32(region+20);h_assert(ee_u32(sh+4)!=8 && address>=base && address-base<=length && size<=length-(address-base),h_cat("cached allocated section is outside emitted .irom/.drom: ",ee_string(load64(elf+32),load64(elf+40),ee_u32(sh))));}
        }si=si+1;
    }
    let code_flash=ee_u32(layout);let code_pages=ee_u32(layout+4);let data_flash=ee_u32(layout+8);let data_pages=ee_u32(layout+12);
    h_assert(code_flash==0x30000 && code_pages==(ee_u32(code+20)+65535)/65536 && data_flash==code_flash+code_pages*65536 && data_pages==(data_size+65535)/65536,"invalid XIP layout");
    h_assert(rom_size<=code_flash-flash_offset && data_flash+data_pages*65536<=0x400000,"XIP payload overlaps RAM image or exceeds flash");let size=data_flash+data_pages*65536-flash_offset;let out=h_take(size);let i=0;while i<size {store8(out+i,255);i=i+1;}h_copy(out,rom,rom_size);h_copy(out+code_flash-flash_offset,ee_payload(elf,code),ee_u32(code+20));if data_size {h_copy(out+data_flash-flash_offset,ee_payload(elf,data),data_size);}h_file_size=size;return out;
}
