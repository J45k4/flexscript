// Wrap a verified compiler ROM image as an ELF32 RAM image for espflash --ram.
// Copies generated machine code unchanged; no assembler, compiler or linker.
import "lib/build.flex";
fn ram_u16(p,value) {store8(p,value);store8(p+1,value>>8);return 0;}
fn ram_u32(p,value) {let i=0;while i<4 {store8(p+i,value>>(i*8));i=i+1;}return 0;}
fn ram_read32(p) {return load8(p)|(load8(p+1)<<8)|(load8(p+2)<<16)|(load8(p+3)<<24);}
fn main(argc,argv) {
    h_environment(argc,argv);let input=b_option(argc,argv,"--input",0);let output=b_option(argc,argv,"--output",0);h_assert(input && output,"requires --input firmware.bin --output firmware.elf");
    h_assert(!h_equal(h_absolute(input),h_absolute(output)),"input and output must differ");let bytes=h_read(input);let length=h_file_size;
    h_assert(length>=80 && load8(bytes)==233 && load8(bytes+1)==2 && load8(bytes+23)==1,"requires a two-segment hashed Flexscript firmware image");
    h_assert(h_equal(h_sha_bytes(bytes,length-32),h_hex(bytes+length-32,32)),"firmware SHA-256 mismatch");
    let chip=load8(bytes+12)|(load8(bytes+13)<<8);h_assert(chip==0 || chip==9,"unsupported ESP32 chip ID");
    let code_base=0x40380000;let data_base=0x3fcb0000;if !chip {code_base=0x40080000;data_base=0x3ffb0000;}
    let code_size=ram_read32(bytes+28);h_assert(code_size>0 && code_size<=131072 && !(code_size&3) && 40+code_size<length-32,"invalid code segment size");
    let data_at=32+code_size;let data_size=ram_read32(bytes+data_at+4);let entry=ram_read32(bytes+4);
    h_assert(ram_read32(bytes+24)==code_base && ram_read32(bytes+data_at)==data_base && data_size>=16 && data_size<=65536 && !(data_size&3) && data_at+8+data_size<length-32,"invalid load segments");
    h_assert(entry>=code_base+1024 && entry<code_base+code_size,"invalid entry address");
    let checksum=239;let i=0;while i<code_size {checksum=checksum^load8(bytes+32+i);i=i+1;}i=0;while i<data_size {checksum=checksum^load8(bytes+data_at+8+i);i=i+1;}
    let at=data_at+8+data_size;while at%16!=15 {h_assert(load8(bytes+at)==0,"invalid ROM padding");at=at+1;}h_assert(at==length-33 && load8(bytes+at)==checksum,"invalid ROM checksum");
    let string_at=116+code_size+data_size;let section_at=string_at+24;let size=section_at+160;let elf=h_take(size);
    store8(elf,127);h_copy(elf+1,"ELF",3);store8(elf+4,1);store8(elf+5,1);store8(elf+6,1);
    ram_u16(elf+16,2);ram_u16(elf+18,94);ram_u32(elf+20,1);ram_u32(elf+24,entry);ram_u32(elf+28,52);ram_u32(elf+32,section_at);
    ram_u16(elf+40,52);ram_u16(elf+42,32);ram_u16(elf+44,2);ram_u16(elf+46,40);ram_u16(elf+48,4);ram_u16(elf+50,3);
    i=0;while i<2 {
        let address=code_base;let n=code_size;let offset=116;let src=bytes+32;let flags=5;let sf=6;
        if i {address=data_base;n=data_size;offset=116+code_size;src=bytes+data_at+8;flags=6;sf=3;}
        let ph=elf+52+i*32;ram_u32(ph,1);ram_u32(ph+4,offset);ram_u32(ph+8,address);ram_u32(ph+12,address);ram_u32(ph+16,n);ram_u32(ph+20,n);ram_u32(ph+24,flags);ram_u32(ph+28,4);
        let sh=elf+section_at+40+i*40;ram_u32(sh,1+i*6);ram_u32(sh+4,1);ram_u32(sh+8,sf);ram_u32(sh+12,address);ram_u32(sh+16,offset);ram_u32(sh+20,n);ram_u32(sh+32,4);h_copy(elf+offset,src,n);i=i+1;
    }
    h_copy(elf+string_at+1,".text",5);h_copy(elf+string_at+7,".data",5);h_copy(elf+string_at+13,".shstrtab",9);
    let sh=elf+section_at+120;ram_u32(sh,13);ram_u32(sh+4,3);ram_u32(sh+16,string_at);ram_u32(sh+20,23);ram_u32(sh+32,1);
    h_save_bytes(output,elf,size,420);h_print(1,h_cat("RAM ELF: ",output));h_print(1,"\n");return 0;
}
