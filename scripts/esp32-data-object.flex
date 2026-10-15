import "lib/esp32-elf.flex";
// Define zero-initialized, writable vendor ABI objects without a C compiler.
fn main(argc,argv) {
    h_environment(argc,argv);let name=b_option(argc,argv,"--symbol",0);let path=b_option(argc,argv,"--output",0);let count=h_number(b_option(argc,argv,"--size","4"));
    h_assert(name && path && ee_valid_symbol(name) && count>0 && count<=32768,"requires --symbol identifier --size bytes --output data.o");
    let data=52;let sym=(data+count+3)&~3;let strings=sym+32;let names=strings+h_len(name)+2;let labels=".data,.symtab,.strtab,.shstrtab,";let ns=h_len(labels)+1;let sh=(names+ns+3)&~3;let size=sh+200;let out=h_take(size);
    ee_w32(out,0x464c457f);store8(out+4,1);store8(out+5,1);store8(out+6,1);ee_w16(out+16,1);ee_w16(out+18,94);ee_w32(out+20,1);ee_w32(out+32,sh);ee_w16(out+40,52);ee_w16(out+46,40);ee_w16(out+48,5);ee_w16(out+50,4);
    ee_w32(out+sym+16,1);ee_w32(out+sym+24,count);store8(out+sym+28,17);ee_w16(out+sym+30,1);h_copy(out+strings+1,name,h_len(name));
    let i=0;while i<ns-1 {let c=load8(labels+i);if c==44 {c=0;}store8(out+names+1+i,c);i=i+1;}
    let p=out+sh+40;ee_w32(p,1);ee_w32(p+4,1);ee_w32(p+8,3);ee_w32(p+16,data);ee_w32(p+20,count);ee_w32(p+32,4);
    p=out+sh+80;ee_w32(p,7);ee_w32(p+4,2);ee_w32(p+16,sym);ee_w32(p+20,32);ee_w32(p+24,3);ee_w32(p+28,1);ee_w32(p+32,4);ee_w32(p+36,16);
    p=out+sh+120;ee_w32(p,15);ee_w32(p+4,3);ee_w32(p+16,strings);ee_w32(p+20,h_len(name)+2);ee_w32(p+32,1);
    p=out+sh+160;ee_w32(p,23);ee_w32(p+4,3);ee_w32(p+16,names);ee_w32(p+20,ns);ee_w32(p+32,1);
    h_save_bytes(path,out,size,420);return 0;
}
