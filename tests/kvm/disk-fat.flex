import "../../lib/disk-fat.flex";
global phase=0;
fn expect(v) {if !v {syscall(1,2,"FAT32 assertion failed in phase ",32,0,0,0);let p=alloc(2);store8(p,48+phase);store8(p+1,10);syscall(1,2,p,2,0,0,0);syscall(60,1,0,0,0,0,0);}return 0;}
fn put16(p,n) {store8(p,n);store8(p+1,n>>8);return 0;}
fn put32(p,n) {put16(p,n);put16(p+2,n>>16);return 0;}
fn copy(to,from,n) {let i=0;while i<n {store8(to+i,load8(from+i));i=i+1;}return 0;}
fn entry(p,name,cluster,size,attr) {copy(p,name,11);store8(p+11,attr);put16(p+20,cluster>>16);put16(p+26,cluster);put32(p+28,size);return 0;}
fn long_entry(p,name,length,seq,last,checksum) {
    store8(p,seq|last);store8(p+11,15);store8(p+13,checksum);let i=0;while i<13 {let at=(seq-1)*13+i;let c=65535;if at<length {c=load8(name+at);}else if at==length {c=0;}let off=1+i*2;if i>=5 {off=14+(i-5)*2;}if i>=11 {off=28+(i-11)*2;}put16(p+off,c);i=i+1;}return 0;
}
fn read(s,path,size) {let p=fat_read(s,path);expect(p && load64(s+96)==size && !load8(p+size));let i=0;while i<size {expect(load8(p+i)==((i*17+3)&255));i=i+1;}syscall(11,p,size+1,0,0,0,0);return 0;}
fn main() {
    let bytes=134217728;let map=alloc(bytes);let s=alloc(2048);let part=map+1048576;let table=part+16384;let data=part+1064960;
    put16(map+510,0xaa55);store8(map+450,0x0c);put32(map+454,2048);put32(map+458,129024);
    put16(part+510,0xaa55);put16(part+11,512);store8(part+13,1);put16(part+14,32);store8(part+16,2);put32(part+32,129024);put32(part+36,1024);put32(part+44,2);
    put32(table,0x0ffffff8);put32(table+4,0xffffffff);let i=2;while i<=8 {put32(table+i*4,0x0fffffff);i=i+1;}put32(table+6*4,8);put32(table+8*4,7);
    entry(data,"EFI        ",3,0,16);entry(data+32,"KERNEL  BIN",5,4,32);entry(data+512,"LINUX      ",4,0,16);
    let directory=data+1024;let alias="OMARCH~1EFI";let name="omarchy_linux-omarchy.efi";let n=25;
    // The long boot name crosses two LFN records; the file chain is fragmented.
    long_entry(directory,name,n,2,64,fat_checksum(alias));long_entry(directory+32,name,n,1,0,fat_checksum(alias));entry(directory+64,alias,6,1200,32);
    i=0;while i<1200 {let cluster=6;if i>=512 {cluster=8;}if i>=1024 {cluster=7;}store8(data+(cluster-2)*512+(i&511),i*17+3);i=i+1;}
    i=0;while i<4 {store8(data+1536+i,i*17+3);i=i+1;}
    expect(fat_init(s,map,bytes,1));read(s,"/EFI/Linux/omarchy_linux-omarchy.efi",1200);read(s,"/efi/linux/OMARCH~1.EFI",1200);read(s,"/kernel.bin",4);
    expect(!fat_read(s,"/") && !fat_read(s,"/EFI/../KERNEL.BIN") && !fat_read(s,"/EFI//LINUX/a") && !fat_read(s,"/EFI/") && !fat_read(s,"/KERNEL.BIN/a"));
    phase=1;store8(directory+13,0);expect(!fat_read(s,"/EFI/Linux/omarchy_linux-omarchy.efi"));store8(directory+13,fat_checksum(alias));
    store8(directory+32,2);expect(!fat_read(s,"/EFI/Linux/omarchy_linux-omarchy.efi"));store8(directory+32,1);
    phase=2;put32(table+8*4,6);expect(!fat_read(s,"/EFI/Linux/OMARCH~1.EFI"));put32(table+8*4,7);
    put32(table+7*4,8);expect(!fat_read(s,"/EFI/Linux/OMARCH~1.EFI"));put32(table+7*4,0x0fffffff);
    put32(table+6*4,0x0fffffff);expect(!fat_read(s,"/EFI/Linux/OMARCH~1.EFI"));put32(table+6*4,8);
    put32(table+6*4,load64(s+72)+1);expect(!fat_read(s,"/EFI/Linux/OMARCH~1.EFI"));put32(table+6*4,8);
    phase=3;copy(table+524288,table,524288);put16(part+40,0x81);put32(table+6*4,0);
    expect(fat_init(s,map,bytes,1));read(s,"/EFI/Linux/OMARCH~1.EFI",1200);put16(part+40,0);put32(table+6*4,8);
    put16(part+40,0x82);expect(!fat_init(s,map,bytes,1));put16(part+40,0);
    phase=4;put32(part+32,129025);expect(!fat_init(s,map,bytes,1));put32(part+32,129024);
    put32(map+458,0xffffffff);expect(!fat_init(s,map,bytes,1));put32(map+458,129024);
    store8(part+13,3);expect(!fat_init(s,map,bytes,1));store8(part+13,1);put32(part+44,0xffffffff);expect(!fat_init(s,map,bytes,1));put32(part+44,2);
    // The same FAT32 volume behind a checksummed GPT partition array.
    phase=5;store8(map+450,0xee);let h=map+512;copy(h,"EFI PART",8);put32(h+8,0x10000);put32(h+12,92);store64(h+24,1);store64(h+32,bytes/512-1);store64(h+40,34);store64(h+48,bytes/512-34);store64(h+72,2);put32(h+80,128);put32(h+84,128);
    let g=map+1024;store64(g,1);store64(g+32,2048);store64(g+40,131071);put32(h+88,fat_crc(g,16384,0));put32(h+16,fat_crc(h,92,1));
    expect(fat_init(s,map,bytes,1));read(s,"/EFI/Linux/omarchy_linux-omarchy.efi",1200);
    phase=6;store8(h+56,1);expect(!fat_init(s,map,bytes,1));store8(h+56,0);store8(g+16,1);expect(!fat_init(s,map,bytes,1));store8(g+16,0);
    store64(g+40,bytes/512);put32(h+88,fat_crc(g,16384,0));put32(h+16,fat_crc(h,92,1));expect(!fat_init(s,map,bytes,1));
    syscall(11,map,bytes,0,0,0,0);syscall(11,s,2048,0,0,0,0);syscall(1,1,"PASS: FAT32 boot files, long names, fragmented chains and GPT bounds\n",69,0,0,0);return 0;
}
