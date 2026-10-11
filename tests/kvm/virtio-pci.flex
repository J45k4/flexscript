import "../../lib/pc-virtio-pci.flex";
import "../../lib/pc-pci.flex";
fn expect(v) {if !v {syscall(1,2,"modern virtio PCI assertion failed\n",35,0,0,0);syscall(60,1,0,0,0,0,0);}return 0;}
fn put(s,off,width,value) {let p=alloc(8);store64(p,value);let r=vp_io(s,load64(s+16)+off,width,1,p,1);syscall(11,p,8,0,0,0,0);return r;}
fn get(s,off,width) {let p=alloc(8);expect(vp_io(s,load64(s+16)+off,width,0,p,1)==1);let v=load64(p);syscall(11,p,8,0,0,0,0);return v;}
fn config(s,pci,off,width,out,value) {let p=alloc(8);store64(p,value);store64(pci,load64(s+32)+(off&252));expect(vp_pci(s,pci,0xcfc+(off&3),width,out,p,1)==1);let result=load64(p);syscall(11,p,8,0,0,0,0);return result;}
fn setup(s,index,base) {
    expect(put(s,22,2,index)==1 && put(s,24,2,64)==1);
    expect(put(s,32,4,base)==1 && put(s,36,4,0)==1);
    expect(put(s,40,4,base+0x1000)==1 && put(s,44,4,0)==1);
    expect(put(s,48,4,base+0x2000)==1 && put(s,52,4,0)==1);return 0;
}
fn main() {
    let s=alloc(8192);let ram=alloc(65536);let pci=alloc(272);let data=alloc(8);pc_pci_init(pci,1);
    expect(vp_init(s,ram,65536,16,0x030000,3,0,2)<0);
    expect(vp_init(s,ram,65536,16,0x030000,3,0x500000000,2)<0); // Packed rings are not implemented.
    expect(vp_init(s,ram,65536,16,0x030000,3,0x100000000,2)==1);
    expect(config(s,pci,0,4,0,0)==0x10501af4 && config(s,pci,8,4,0,0)==0x03000001);
    expect(config(s,pci,6,2,0,0)==16 && config(s,pci,0x34,1,0,0)==0x40);
    // Configuration-space access is usable before assigning/enabling an I/O BAR.
    config(s,pci,0x8c,4,1,18);config(s,pci,0x90,4,1,2);expect(config(s,pci,0x94,2,0,0)==2);
    // Walk the advertised standard capability list as a driver would.
    let at=0x40;let types=0;let count=0;while at {expect(config(s,pci,at,1,0,0)==9);let type=config(s,pci,at+3,1,0,0);types=types|(1<<type);expect(config(s,pci,at+4,1,0,0)==0);at=config(s,pci,at+1,1,0,0);count=count+1;expect(count<=5);}
    expect(types==62 && count==5 && config(s,pci,0x60,4,0,0)==2);
    config(s,pci,16,4,1,0xffffffff);expect(config(s,pci,16,4,0,0)==0xffffff01);config(s,pci,16,4,1,0xc301);
    expect(load64(s+16)==0xc300 && !vp_io(s,0xc100,4,0,data,1));expect(!vp_io(s,0xc300,4,0,data,1));config(s,pci,4,2,1,5);
    expect(get(s,4,4)==0 && put(s,0,4,1)==1 && get(s,4,4)==1);expect(put(s,0,4,2)==1 && get(s,4,4)==0);
    expect(put(s,8,4,0)==1 && put(s,12,4,1)==1 && put(s,8,4,1)==1 && put(s,12,4,1)==1);
    expect(put(s,20,1,11)==1 && get(s,20,1)==3); // Unsupported low feature rejected via FEATURES_OK.
    expect(put(s,20,1,0)==1 && get(s,20,1)==0 && get(s,18,2)==2);
    expect(put(s,8,4,1)==1 && put(s,12,4,1)==1 && put(s,20,1,11)==1 && get(s,20,1)==11);
    expect(put(s,12,4,0)<0); // Negotiated features cannot silently change.
    expect(put(s,22,2,2)==1 && get(s,24,2)==0 && get(s,28,2)==0);
    setup(s,0,0x1000);expect(put(s,28,2,1)==1 && get(s,28,2)==1 && get(s,30,2)==0);
    expect(put(s,32,4,0x8000)<0);setup(s,1,0x1000);expect(put(s,28,2,1)<0); // Cross-queue overlap rejected.
    setup(s,1,0x8000);expect(put(s,28,2,1)==1 && get(s,30,2)==1);
    expect(put(s,64,2,0)<0 && put(s,20,1,15)==1);expect(put(s,64,2,0)==1 && put(s,66,2,1)==1 && load64(s+120)==3);
    expect(put(s,64,2,1)<0 && put(s,66,2,2)<0);
    store64(s+88,3);expect(vp_irq(s) && !vp_irq(s) && get(s,68,1)==3 && !vp_irq(s));
    kvm_put32(s+512+8,1);expect(get(s,88,4)==1 && get(s,88,1)==1 && get(s,89,1)==0);
    // The PCI configuration access capability reaches the same registers.
    config(s,pci,0x8c,4,1,88);config(s,pci,0x90,4,1,4);expect(config(s,pci,0x94,4,0,0)==1);
    config(s,pci,0x8c,4,1,22);config(s,pci,0x90,4,1,2);config(s,pci,0x94,2,1,0);expect(get(s,22,2)==0);
    config(s,pci,0x8c,4,1,64);config(s,pci,0x94,2,1,0);expect(load64(s+120)==3);
    expect(put(s,20,1,0)==1 && !load64(s+120) && get(s,24,2)==128 && !get(s,28,2));
    // Reject high addresses, unaligned rings, zero/non-power-of-two sizes,
    // and local overlap before enabling any DMA queue.
    expect(put(s,24,2,0)<0 && put(s,24,2,3)<0 && put(s,24,2,256)<0);
    setup(s,0,0x1000);expect(put(s,36,4,1)==1 && put(s,28,2,1)<0);expect(put(s,36,4,0)==1);
    expect(put(s,32,4,0x1001)==1 && put(s,28,2,1)<0);expect(put(s,32,4,0x1000)==1);
    expect(put(s,40,4,0x1010)==1 && put(s,28,2,1)<0);expect(put(s,40,4,65534)==1 && put(s,28,2,1)<0);
    syscall(1,1,"PASS: modern virtio PCI transport and bounded split queues\n",58,0,0,0);return 0;
}
