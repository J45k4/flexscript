import "../../emulator/pc/virtio-net.flex";
global stage=0;
fn expect(ok) {if !ok {syscall(1,2,"virtio-net assertion failed at stage ",36,0,0,0);let p=alloc(8);store8(p,48+stage);store8(p+1,10);syscall(1,2,p,2,0,0,0);syscall(60,1,0,0,0,0,0);}return 0;}
fn reg(s,off,width,value) {let p=alloc(8);store64(p,value);let r=vn_io(s,load64(s+16)+off,width,1,p,1);syscall(11,p,8,0,0,0,0);return r;}
fn queue(s,index,base) {expect(reg(s,22,2,index)==1 && reg(s,24,2,8)==1);expect(reg(s,32,4,base)==1 && reg(s,40,4,base+0x1000)==1 && reg(s,48,4,base+0x2000)==1 && reg(s,28,2,1)==1);return 0;}
fn descriptor(ram,base,index,address,size,flags,next) {let p=ram+base+index*16;store64(p,address);kvm_put32(p+8,size);vp_put16(p+12,flags);vp_put16(p+14,next);return 0;}
fn be16(p,n) {store8(p,n>>8);store8(p+1,n);return 0;}
fn word(p) {return (load8(p)<<8)|load8(p+1);}
fn arp(s,ram) {
    let p=ram+0xb00c;kvm_zero(ram+0xb000,54);let i=0;while i<6 {store8(p+i,255);store8(p+6+i,load8(s+512+i));store8(p+22+i,load8(s+512+i));i=i+1;}
    be16(p+12,0x806);be16(p+14,1);be16(p+16,0x800);store8(p+18,6);store8(p+19,4);be16(p+20,1);store8(p+28,10);store8(p+30,2);store8(p+31,15);store8(p+38,10);store8(p+40,2);store8(p+41,2);return 0;
}
fn main() {
    let s=alloc(24576);let ram=alloc(65536);expect(vn_init(s,ram,65536,1)==1);
    expect(load64(s+40)==0x100010020 && load8(s+256+60)==5 && vp_u16(s+512+6)==1 && load8(s+512)==0x52);
    store64(s+24,5);expect(reg(s,8,4,0)==1 && reg(s,12,4,0x10020)==1 && reg(s,8,4,1)==1 && reg(s,12,4,1)==1 && reg(s,20,1,11)==1);
    queue(s,0,0x1000);queue(s,1,0x8000);expect(reg(s,20,1,15)==1);
    // Real ARP exchange through both guest queues and the bounded NAT backend.
    // Headers and Ethernet payload cross descriptor boundaries in both directions.
    stage=1;arp(s,ram);descriptor(ram,0x8000,0,0xb000,7,1,1);descriptor(ram,0x8000,1,0xb007,47,0,0);
    descriptor(ram,0x1000,0,0x4000,5,3,1);descriptor(ram,0x1000,1,0x5000,2043,2,0);
    vp_put16(ram+0x2004,0);vp_put16(ram+0x2002,1);vp_put16(ram+0x9004,0);vp_put16(ram+0x9002,1);
    expect(reg(s,66,2,1)==1 && vn_tick(s)>0);
    expect(vp_u16(ram+0xa002)==1 && !kvm_u32(ram+0xa008) && vp_u16(ram+0x3002)==1 && kvm_u32(ram+0x3008)>=54);
    expect(!load8(ram+0x4000) && !load8(ram+0x4001) && vp_u16(ram+0x5005)==1);
    let p=ram+0x5007;expect(word(p+12)==0x806 && word(p+20)==2 && load8(p+31)==2 && load8(p+41)==15);
    let i=0;while i<6 {expect(load8(p+i)==load8(s+512+i));i=i+1;}expect(vp_irq(s) && !vp_irq(s));
    let data=alloc(8);expect(vn_io(s,load64(s+16)+68,1,0,data,1)==1 && load8(data)==1 && !load64(s+88));
    // Invalid RX chains must leave every guest byte and ring counter unchanged.
    stage=2;let backend=load64(s+8192);expect(ffi_call(load64(backend+96),p,42,backend,0,0,0)==42);
    vp_put16(ram+0x2006,0);vp_put16(ram+0x2002,2);
    descriptor(ram,0x1000,0,0x9000,128,2,0);expect(vn_rx(s)<0 && vp_u16(ram+0x3002)==1 && vp_u16(ram+0x9002)==1);
    descriptor(ram,0x1000,0,65530,128,2,0);expect(vn_rx(s)<0 && vp_u16(ram+0x3002)==1);
    descriptor(ram,0x1000,0,0x4000,128,6,0);expect(vn_rx(s)<0);
    descriptor(ram,0x1000,0,0x4000,128,0,0);expect(vn_rx(s)<0);
    descriptor(ram,0x1000,0,0x4000,128,3,0);expect(vn_rx(s)<0); // cycle
    descriptor(ram,0x1000,0,0x4000,30,3,1);descriptor(ram,0x1000,1,0x4010,128,2,0);expect(vn_rx(s)<0); // overlapping segments
    descriptor(ram,0x1000,0,0x4000,30,2,0);expect(vn_rx(s)<0); // short capacity
    descriptor(ram,0x1000,0,0x4000,2048,2,0);expect(vn_rx(s)==2 && vp_u16(ram+0x3002)==2 && !sn_peek(backend));
    // Both split-ring counters wrap; NO_INTERRUPT suppresses IRQ, not DMA.
    stage=3;vp_irq(s);expect(vn_io(s,load64(s+16)+68,1,0,data,1)==1);let q=vp_queue(s,0);store64(q+40,65535);store64(q+48,65535);
    vp_put16(ram+0x2000,1);vp_put16(ram+0x2002,0);vp_put16(ram+0x2012,0);expect(ffi_call(load64(backend+96),p,42,backend,0,0,0)==42);
    expect(vn_rx(s)==2 && !load64(q+40) && !load64(q+48) && !vp_u16(ram+0x3002) && kvm_u32(ram+0x3040)==54 && !load64(s+88));
    vp_put16(ram+0x2002,9);expect(ffi_call(load64(backend+96),p,42,backend,0,0,0)==42);expect(vn_rx(s)<0 && !load64(q+40));sn_pop(backend);
    // Malformed TX frames, directions and cycles never consume a descriptor.
    stage=4;vp_put16(ram+0x9006,0);vp_put16(ram+0x9002,2);descriptor(ram,0x8000,0,0xb000,54,2,0);expect(vn_tx(s)<0);
    descriptor(ram,0x8000,0,0xb000,54,1,0);expect(vn_tx(s)<0);
    descriptor(ram,0x8000,0,0xb000,25,0,0);expect(vn_tx(s)<0);
    descriptor(ram,0x8000,0,0xb000,54,0,0);store8(ram+0xb000,1);expect(vn_tx(s)<0 && vp_u16(ram+0xa002)==1);store8(ram+0xb000,0);
    expect(vn_tx(s)==1 && vp_u16(ram+0xa002)==2);
    // Reset disables queues and drops pending host frames, keeping the backend
    // owned until close. Repeated close must be harmless.
    stage=5;expect(reg(s,20,1,0)==1 && !load64(q+8) && !sn_peek(backend));vn_close(s);vn_close(s);expect(!load64(s+8192));
    syscall(1,1,"PASS: virtio-net ARP, scatter DMA, queue wrap, bounds and reset\n",64,0,0,0);return 0;
}
