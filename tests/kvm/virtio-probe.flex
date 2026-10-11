// Exercise PCI discovery and a split-ring sector read through actual monitor
// IN/OUT exits and guest DMA. Backing fixture is 4096 bytes: byte[i]=i*17+3.
fn expect(v) {if !v {port_out8(0x3f8,70);cpu_halt();}return 0;}
fn pci(reg) {port_out32(0xcf8,0x80000800+reg);return port_in32(0xcfc);}
fn write_pci(reg,value) {port_out32(0xcf8,0x80000800+reg);port_out32(0xcfc,value);return 0;}
fn main() {
    expect(pci(0)==0x10011af4);write_pci(16,0xffffffff);expect(pci(16)==0xffffffc1);write_pci(16,0xc001);write_pci(4,5);
    let capacity=port_in32(0xc014);expect(port_in32(0xc000)==38 && capacity>=8 && port_in16(0xc00c)==128);
    port_out8(0xc012,0);port_out8(0xc012,1);port_out8(0xc012,3);port_out32(0xc004,38);port_out16(0xc00e,0);port_out32(0xc008,0x300);port_out8(0xc012,7);
    expect(port_in32(0xc01c)==65536 && port_in32(0xc020)==126);
    // Header at 0x304000, data at 0x305000, status at 0x306000.
    store64(0x300000,0x304000);store64(0x300008,0x0001000100000010);
    store64(0x300010,0x305000);store64(0x300018,0x0002000300000200);
    store64(0x300020,0x306000);store64(0x300028,0x0000000200000001);
    let sector=3;if capacity>8 {sector=64;}store64(0x304000,0);store64(0x304008,sector);store8(0x306000,0xff);
    store64(0x300800,0x10000);port_out16(0xc010,0);
    expect(load8(0x306000)==0 && load8(0x301002)==1 && load64(0x301004)==0x0000020100000000);
    let i=0;if capacity==8 {while i<512 {expect(load8(0x305000+i)==(((1536+i)*17+3)&255));i=i+1;}}else {
        expect(load8(0x305000)==1 && load8(0x305006)==1);i=0;while i<5 {expect(load8(0x305001+i)==load8("CD001"+i));i=i+1;}
    }
    expect(port_in8(0xc013)==1 && port_in8(0xc013)==0);
    let text="virtio block probe passed\n";if capacity>8 {text="virtio ISO sector probe passed\n";}
    port_out32(0xcf8,0x80001000);if port_in32(0xcfc)==0x10011af4 {
        port_out32(0xcf8,0x80001004);port_out32(0xcfc,5);expect(port_in32(0xc040)==518);
        port_out8(0xc052,3);port_out32(0xc044,518);port_out16(0xc04e,0);port_out32(0xc048,0x310);port_out8(0xc052,7);
        store64(0x310000,0x314000);store64(0x310008,0x0001000100000010);store64(0x310010,0x315000);store64(0x310018,0x0002000100000200);store64(0x310020,0x316000);store64(0x310028,0x0000000200000001);
        store64(0x314000,1);store64(0x314008,1);store8(0x316000,255);i=0;while i<512 {store8(0x315000+i,i*13+7);i=i+1;}
        store64(0x310800,0x10000);port_out16(0xc050,0);expect(!load8(0x316000) && load64(0x311004)==0x0000000100000000);
        // Flush with only the header and status descriptor, then read it back.
        store64(0x314000,4);store64(0x314008,0);store64(0x310010,0x316000);store64(0x310018,0x0000000200000001);store8(0x310802,2);port_out16(0xc050,0);expect(!load8(0x316000));
        store64(0x314000,0);store64(0x314008,1);store64(0x310010,0x315000);store64(0x310018,0x0002000300000200);i=0;while i<512 {store8(0x315000+i,0);i=i+1;}
        store8(0x310802,3);port_out16(0xc050,0);expect(!load8(0x316000));i=0;while i<512 {expect(load8(0x315000+i)==((i*13+7)&255));i=i+1;}
        expect(port_in8(0xc053)==1);text="virtio media and disk probe passed\n";
    }
    i=0;while load8(text+i) {port_out8(0x3f8,load8(text+i));i=i+1;}cpu_halt();return 0;
}
