// Execute real PCI/port exits and GPU DMA from a guest on both CPU backends.
// No host resource API calls or host-written response bytes are involved.
global submitted=0;
fn expect(v) {if !v {port_out8(0x3f8,70);cpu_halt();}return 0;}
fn pci(reg) {port_out32(0xcf8,0x80001800+reg);return port_in32(0xcfc);}
fn write_pci(reg,value) {port_out32(0xcf8,0x80001800+reg);port_out32(0xcfc,value);return 0;}
fn request(type,n) {
    store64(0x304000,type);store64(0x304008,0);store64(0x304010,0);
    store64(0x300000,0x304000);store64(0x300008,n|0x0001000100000000);
    store64(0x300010,0x305000);store64(0x300018,0x0000000200000198);
    store8(0x301004+(submitted&7)*2,0);submitted=submitted+1;
    store8(0x301002,submitted);store8(0x301003,0);port_out16(0xc140,0);
    expect(load8(0x302002)==submitted && port_in8(0xc144)==1 && port_in8(0xc144)==0);
    return load64(0x305000)&0xffffffff;
}
fn main() {
    expect(pci(0)==0x10501af4 && pci(8)==0x03800001);write_pci(16,0xffffffff);expect(pci(16)==0xffffff01);
    write_pci(16,0xc101);write_pci(4,5);
    expect(port_in16(0xc112)==2 && port_in32(0xc158)==1);
    port_out32(0xc100,1);expect(port_in32(0xc104)==1);port_out32(0xc108,1);port_out32(0xc10c,1);port_out8(0xc114,11);
    expect(port_in8(0xc114)==11);port_out16(0xc116,0);port_out16(0xc118,8);
    port_out32(0xc120,0x300000);port_out32(0xc128,0x301000);port_out32(0xc130,0x302000);port_out16(0xc11c,1);port_out8(0xc114,15);
    expect(request(0x100,24)==0x1101 && load64(0x305020)==0x0000030000000400 && load8(0x305028)==1);
    store64(0x304018,0x0000000200000001);store64(0x304020,0x0000000200000002);expect(request(0x101,40)==0x1100);
    store64(0x304018,0x0000000100000001);store64(0x304020,0x306000);store64(0x304028,16);expect(request(0x106,48)==0x1100);
    store64(0x306000,0x0000ff0000ff0000);store64(0x306008,0x00ffffff000000ff);
    store64(0x304018,0);store64(0x304020,0x0000000200000002);store64(0x304028,0);store64(0x304030,1);expect(request(0x105,56)==0x1100);
    store64(0x304028,0x0000000100000000);expect(request(0x103,48)==0x1100);
    store64(0x304028,1);expect(request(0x104,48)==0x1100);
    expect(request(0x200,24)==0x1200);
    port_out8(0xc114,0);expect(!port_in8(0xc114) && !port_in16(0xc11c));
    let text="virtio GPU guest probe passed\n";let i=0;while load8(text+i) {port_out8(0x3f8,load8(text+i));i=i+1;}cpu_halt();return 0;
}
