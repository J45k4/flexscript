import "../../emulator/pc/virtio-blk.flex";
import "../../emulator/pc/pci.flex";
fn expect(v) {if !v {syscall(1,2,"virtio block assertion failed\n",30,0,0,0);if vb_message {let n=0;while load8(vb_message+n) {n=n+1;}syscall(1,2,vb_message,n,0,0,0);}syscall(60,1,0,0,0,0,0);}return 0;}
fn reg(s,off,width,value) {let p=alloc(8);store64(p,value);let r=vb_io(s,load64(s+32)+off,width,1,p,1);syscall(11,p,8,0,0,0,0);return r;}
fn desc(ram,index,address,length,flags,next) {let d=ram+0x1000+index*16;store64(d,address);kvm_put32(d+8,length);vb_put16(d+12,flags);vb_put16(d+14,next);return 0;}
fn submit(s,ram,type,sector) {kvm_put32(ram+0x4000,type);store64(ram+0x4008,sector);store8(ram+0x5000,0xff);let n=load64(s+88);vb_put16(ram+0x1804+(n&127)*2,0);vb_put16(ram+0x1802,(n+1)&65535);return reg(s,16,2,0);}
fn main(argc,argv) {
    expect(argc==3);let s=alloc(4096);let ram=alloc(65536);let pci=alloc(272);let data=alloc(8);pc_pci_init(pci,1);
    expect(vb_open(s,"/dev/null",ram,65536)<0 && !load64(s));
    expect(vb_open_mode(s,"/dev/null",ram,65536,1,2)<0 && !load64(s));
    expect(vb_open(s,load64(argv+8),ram,65536)==1 && load64(s+8)==4096);
    store64(pci,0x80000800);expect(vb_pci(s,pci,0xcfc,4,0,data,1) && kvm_u32(data)==0x10011af4);
    store64(pci,0x80000810);kvm_put32(data,0xffffffff);expect(vb_pci(s,pci,0xcfc,4,1,data,1));expect(vb_pci(s,pci,0xcfc,4,0,data,1) && kvm_u32(data)==0xffffffc1);
    kvm_put32(data,0xc001);expect(vb_pci(s,pci,0xcfc,4,1,data,1));
    expect(!vb_io(s,0xc000,4,0,data,1));store64(pci,0x80000804);kvm_put32(data,5);expect(vb_pci(s,pci,0xcfc,2,1,data,1));
    expect(vb_io(s,0xc000,4,0,data,1)==1 && kvm_u32(data)==38);expect(reg(s,4,4,0x10000000)<0);expect(reg(s,4,4,38)==1);
    expect(reg(s,14,2,1)==1 && vb_io(s,0xc00c,2,0,data,1)==1 && vb_u16(data)==0);expect(reg(s,14,2,0)==1);
    expect(vb_io(s,0xc014,4,0,data,1)==1 && kvm_u32(data)==8);
    expect(vb_io(s,0xc01c,4,0,data,1)==1 && kvm_u32(data)==65536 && vb_io(s,0xc020,4,0,data,1)==1 && kvm_u32(data)==126);
    expect(reg(s,8,4,1)==1 && reg(s,18,1,7)==1);
    desc(ram,0,0x4000,16,1,1);desc(ram,1,0x6000,256,3,2);desc(ram,2,0x7000,256,3,3);desc(ram,3,0x5000,1,2,0);
    expect(submit(s,ram,0,2)==1 && !load8(ram+0x5000) && vb_u16(ram+0x2002)==1);
    let i=0;while i<256 {expect(load8(ram+0x6000+i)==(((1024+i)*17+3)&255));expect(load8(ram+0x7000+i)==(((1280+i)*17+3)&255));i=i+1;}
    expect(kvm_u32(ram+0x2008)==513 && vb_irq(s) && !vb_irq(s));expect(vb_io(s,0xc013,1,0,data,1) && load8(data)==1 && !vb_irq(s));
    // Data bounds fail as an ordinary IOERR, and a write cannot alter the file.
    expect(submit(s,ram,0,8)==1 && load8(ram+0x5000)==1);desc(ram,1,0x6000,256,1,2);desc(ram,2,0x7000,256,1,3);expect(submit(s,ram,1,0)==1 && load8(ram+0x5000)==1);desc(ram,1,0x6000,256,3,2);desc(ram,2,0x7000,256,3,3);
    expect(submit(s,ram,4,0)==1 && load8(ram+0x5000)==2);
    expect(submit(s,ram,8,0)==1 && !load8(ram+0x5000) && load8(ram+0x6000)==70 && kvm_u32(ram+0x2028)==21);
    // Interrupt suppression and 16-bit ring wrap.
    vb_io(s,0xc013,1,0,data,1);vb_put16(ram+0x1800,1);store64(s+88,65535);store64(s+96,65535);
    expect(submit(s,ram,0,0)==1 && !load64(s+88) && !load64(s+96) && !vb_irq(s) && !vb_u16(ram+0x2002));
    // Malformed chains cannot write even the status byte.
    desc(ram,2,65530,256,3,3);expect(submit(s,ram,0,0)<0 && load8(ram+0x5000)==255);desc(ram,2,0x7000,256,3,3);
    desc(ram,1,0x1000,256,3,2);expect(reg(s,16,2,0)<0 && load8(ram+0x5000)==255);desc(ram,1,0x6000,256,3,2);
    desc(ram,2,0x7000,256,7,3);expect(reg(s,16,2,0)<0);desc(ram,2,0x7000,256,3,1);expect(reg(s,16,2,0)<0);
    expect(reg(s,18,1,0)==1 && !load64(s+48) && !load64(s+72) && !load64(s+104));expect(reg(s,16,2,0)<0);
    vb_close(s);expect(!load64(s));
    // A separate regular file is writable, flushable and survives reopening.
    expect(vb_open_mode(s,load64(argv+16),ram,65536,1,2)==1 && vb_features(s)==518 && load64(s+144)==10);
    store64(pci,0x80001000);expect(vb_pci(s,pci,0xcfc,4,0,data,1) && kvm_u32(data)==0x10011af4);
    store64(s+40,5);kvm_zero(ram+0x1000,8192);expect(reg(s,4,4,518)==1 && reg(s,8,4,1)==1 && reg(s,18,1,7)==1);
    i=0;while i<512 {store8(ram+0x6000+i,i*13+7);i=i+1;}desc(ram,0,0x4000,16,1,1);desc(ram,1,0x6000,512,1,2);desc(ram,2,0x5000,1,2,0);
    expect(submit(s,ram,1,2)==1 && !load8(ram+0x5000) && kvm_u32(ram+0x2008)==1);
    desc(ram,1,0x5000,1,2,0);expect(submit(s,ram,4,0)==1 && !load8(ram+0x5000));vb_close(s);
    expect(vb_open_mode(s,load64(argv+16),ram,65536,1,2)==1);store64(s+40,5);kvm_zero(ram+0x1000,8192);expect(reg(s,8,4,1)==1 && reg(s,18,1,7)==1);
    desc(ram,0,0x4000,16,1,1);desc(ram,1,0x6000,512,3,2);desc(ram,2,0x5000,1,2,0);kvm_zero(ram+0x6000,512);
    expect(submit(s,ram,0,2)==1 && !load8(ram+0x5000));i=0;while i<512 {expect(load8(ram+0x6000+i)==((i*13+7)&255));i=i+1;}
    expect(syscall(17,load64(s)-1,ram+0x8000,4096,0,0,0)==4096 && !load8(ram+0x8000) && !load8(ram+0x8800) && load8(ram+0x8400)==7);
    vb_close(s);
    // Large legacy requests must work even without SIZE_MAX negotiation.
    // A newly negotiated driver gets explicit 64-KiB segments and 126 data
    // descriptors, and violations fail before guest RAM or file changes.
    let fd=syscall(2,load64(argv+16),2,0,0,0,0);expect(fd>=0 && syscall(77,fd,16777216,0,0,0,0)==0);store64(data,0x1122334455667788);expect(syscall(18,fd,data,8,2097144,0,0)==8);syscall(3,fd,0,0,0,0,0);
    let large=alloc(33554432);expect(vb_open_mode(s,load64(argv+16),large,33554432,1,2)==1);store64(s+40,5);expect(reg(s,8,4,1)==1 && reg(s,18,1,7)==1);
    desc(large,0,0x4000,16,1,1);desc(large,1,0x100000,2097152,3,2);desc(large,2,0x5000,1,2,0);
    expect(submit(s,large,0,0)==1 && !load8(large+0x5000) && load64(large+0x2ffff8)==0x1122334455667788 && kvm_u32(large+0x2008)==2097153);
    expect(reg(s,4,4,518)==1 && submit(s,large,0,0)<0 && load8(large+0x5000)==255);
    i=1;while i<=32 {desc(large,i,0x100000+(i-1)*65536,65536,3,i+1);i=i+1;}desc(large,33,0x5000,1,2,0);store64(large+0x2ffff8,0);
    expect(reg(s,16,2,0)==1 && !load8(large+0x5000) && load64(large+0x2ffff8)==0x1122334455667788);
    expect(reg(s,4,4,512)==1);desc(large,1,0x100000,8389120,3,2);desc(large,2,0x5000,1,2,0);expect(submit(s,large,0,0)==1 && !load8(large+0x5000));
    i=1;while i<=17 {desc(large,i,0x100000,8388608,3,i+1);i=i+1;}desc(large,18,0x5000,1,2,0);expect(submit(s,large,0,0)<0 && load8(large+0x5000)==255);
    vb_close(s);syscall(11,large,33554432,0,0,0,0);syscall(1,1,"virtio block tests passed\n",25,0,0,0);return 0;
}
