import "../../emulator/linux/uki.flex";
fn expect(v) {if !v {syscall(1,2,"UKI assertion failed\n",21,0,0,0);syscall(60,1,0,0,0,0,0);}return 0;}
fn put16(p,n) {store8(p,n);store8(p+1,n>>8);return 0;}
fn put32(p,n) {put16(p,n);put16(p+2,n>>16);return 0;}
fn copy(to,from,n) {let i=0;while i<n {store8(to+i,load8(from+i));i=i+1;}return 0;}
fn section(p,name,offset,size) {let i=0;while i<8 && load8(name+i) {store8(p+i,load8(name+i));i=i+1;}put32(p+8,size);put32(p+16,512);put32(p+20,offset);return 0;}
fn main() {
    let image=alloc(4096);let s=alloc(48);put16(image,0x5a4d);put32(image+60,128);let p=image+128;
    put32(p,0x4550);put16(p+4,0x8664);put16(p+6,3);put16(p+20,240);put16(p+24,0x20b);put32(p+24+60,512);
    let table=p+264;section(table,".linux",512,300);section(table+40,".initrd",1024,7);section(table+80,".cmdline",1536,32);
    copy(image+1536,"root=UUID=fixture rootflags=subvol=@",34);
    expect(uki_parse(s,image,4096) && load64(s)==image+512 && load64(s+8)==300 && load64(s+16)==image+1024 && load64(s+24)==7 && load64(s+32)==image+1536 && load64(s+40)==32);
    put32(table+80+8,35);expect(uki_parse(s,image,4096) && load64(s+40)==34);
    put32(table+40+20,768);expect(!uki_parse(s,image,4096));put32(table+40+20,1024);
    put32(table+40+16,4096);expect(!uki_parse(s,image,4096));put32(table+40+16,512);
    put32(table+8,513);expect(!uki_parse(s,image,4096));put32(table+8,300);
    store8(table+40,46);copy(table+41,"linux\0\0",7);expect(!uki_parse(s,image,4096));fat_zero(table+40,8);copy(table+40,".initrd",7);
    put16(p+6,2);expect(!uki_parse(s,image,4096));put16(p+6,3);
    put32(image+60,4090);expect(!uki_parse(s,image,4096));put32(image+60,128);
    put16(p+4,0x14c);expect(!uki_parse(s,image,4096));put16(p+4,0x8664);
    put32(p+24+60,5000);expect(!uki_parse(s,image,4096));put32(p+24+60,512);
    expect(!uki_parse(s,image,63));return 0;
}
