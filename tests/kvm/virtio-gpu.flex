import "../../emulator/pc/virtio-gpu.flex";
fn expect(v) {if !v {syscall(1,2,"virtio GPU assertion failed\n",28,0,0,0);syscall(60,1,0,0,0,0,0);}return 0;}
fn command(s,p,n,out) {expect(vg_command(s,p,n,out,408,0)>0);return kvm_u32(out);}
fn header(p,type) {kvm_zero(p,1024);kvm_put32(p,type);return 0;}
fn create(s,p,out,id,format,w,h) {header(p,0x101);kvm_put32(p+24,id);kvm_put32(p+28,format);kvm_put32(p+32,w);kvm_put32(p+36,h);return command(s,p,40,out);}
fn rect(p,x,y,w,h) {kvm_put32(p+24,x);kvm_put32(p+28,y);kvm_put32(p+32,w);kvm_put32(p+36,h);return 0;}
fn reg(s,off,width,value) {let p=alloc(8);store64(p,value);let result=vg_io(s,load64(s+16)+off,width,1,p,1);syscall(11,p,8,0,0,0,0);return result;}
fn queue(s,index,base) {
    expect(reg(s,22,2,index)==1 && reg(s,24,2,8)==1);
    expect(reg(s,32,4,base)==1 && reg(s,40,4,base+0x1000)==1 && reg(s,48,4,base+0x2000)==1 && reg(s,28,2,1)==1);return 0;
}
fn descriptor(ram,base,index,address,size,flags,next) {let d=ram+base+index*16;store64(d,address);kvm_put32(d+8,size);vp_put16(d+12,flags);vp_put16(d+14,next);return 0;}
fn cfg(s,pci,off,width,value) {let data=alloc(8);store64(data,value);store64(pci,load64(s+32)+(off&252));let result=vg_pci(s,pci,0xcfc+(off&3),width,1,data,1);syscall(11,data,8,0,0,0,0);return result;}
fn cfg_reg(s,pci,off,width,value) {expect(cfg(s,pci,0x8c,4,off)==1 && cfg(s,pci,0x90,4,width)==1);return cfg(s,pci,0x94,width,value);}
fn transport(s,ram,request,output) {
    // Negotiate through the guest-visible I/O registers, then execute a
    // request and response whose headers both cross descriptor boundaries.
    store64(s+24,5);expect(reg(s,8,4,1)==1 && reg(s,12,4,1)==1 && reg(s,20,1,11)==1);
    queue(s,0,0x1000);queue(s,1,0x8000);expect(reg(s,20,1,15)==1);
    header(request,0x100);kvm_put32(request+4,1);store64(request+8,0xfedcba9876543210);
    vg_copy(ram+0x4000,request,12);vg_copy(ram+0x4100,request+12,12);
    descriptor(ram,0x1000,0,0x4000,12,1,1);descriptor(ram,0x1000,1,0x4100,12,1,2);
    descriptor(ram,0x1000,2,0x5000,13,3,3);descriptor(ram,0x1000,3,0x6000,395,2,0);
    vp_put16(ram+0x2004,0);vp_put16(ram+0x2002,1);expect(reg(s,64,2,0)==1);
    vg_copy(output,ram+0x5000,13);vg_copy(output+13,ram+0x6000,395);
    expect(kvm_u32(output)==0x1101 && load64(output+8)==0xfedcba9876543210 && kvm_u32(output+32)==1024 && kvm_u32(output+40)==1);
    expect(vp_u16(ram+0x3002)==1 && kvm_u32(ram+0x3004)==0 && kvm_u32(ram+0x3008)==408 && vp_irq(s) && !vp_irq(s));
    let data=alloc(8);expect(vg_io(s,load64(s+16)+68,1,0,data,1)==1 && load8(data)==1 && !load64(s+88));
    // A CREATE command must not allocate a resource or advance the ring
    // when its response aliases any enabled queue's metadata or its input.
    expect(create(s,request,output,77,2,1,1)==0x1100);vg_free_resource(s,vg_find(s,77));
    vg_copy(ram+0x4000,request,40);descriptor(ram,0x1000,0,0x4000,40,1,1);
    descriptor(ram,0x1000,1,0x9000,24,2,0);vp_put16(ram+0x2006,0);vp_put16(ram+0x2002,2);
    expect(reg(s,64,2,0)<0 && !vg_find(s,77) && vp_u16(ram+0x3002)==1 && !vp_u16(ram+0x9002));
    descriptor(ram,0x1000,1,0x4008,24,2,0);expect(reg(s,64,2,0)<0 && !vg_find(s,77) && kvm_u32(ram+0x4000)==0x101);
    descriptor(ram,0x1000,1,65530,24,2,0);expect(reg(s,64,2,0)<0 && !vg_find(s,77));
    descriptor(ram,0x1000,1,0x5000,24,3,0);expect(reg(s,64,2,0)<0 && !vg_find(s,77)); // cycle
    descriptor(ram,0x1000,1,0x5000,24,6,0);expect(reg(s,64,2,0)<0 && !vg_find(s,77)); // unadvertised INDIRECT
    descriptor(ram,0x1000,1,0x5000,24,3,2);descriptor(ram,0x1000,2,0x6000,24,0,0);
    expect(reg(s,64,2,0)<0 && !vg_find(s,77)); // read after write
    descriptor(ram,0x1000,1,0x5000,24,2,0);expect(reg(s,64,2,0)==1 && vg_find(s,77) && kvm_u32(ram+0x5000)==0x1100 && vp_u16(ram+0x3002)==2);
    // Cursor requests have only readable descriptors and a zero-length used
    // entry. No response DMA is required to complete the cursor queue.
    header(request,0x301);kvm_put32(request+28,123);kvm_put32(request+32,456);vg_copy(ram+0xb000,request,56);
    descriptor(ram,0x8000,0,0xb000,56,0,0);vp_put16(ram+0x9004,0);vp_put16(ram+0x9002,1);
    expect(reg(s,66,2,1)==1 && load64(s+8264)==123 && load64(s+8272)==456 && vp_u16(ram+0xa002)==1 && !kvm_u32(ram+0xa008));
    // Both split-ring counters wrap at 16 bits. NO_INTERRUPT suppresses
    // notification without suppressing the completion or response.
    expect(vg_io(s,load64(s+16)+68,1,0,data,1)==1);vp_irq(s);
    let q=vp_queue(s,0);store64(q+40,65535);store64(q+48,65535);
    header(request,0x200);vg_copy(ram+0x4000,request,24);descriptor(ram,0x1000,0,0x4000,24,1,1);
    vp_put16(ram+0x2000,1);vp_put16(ram+0x2002,0);vp_put16(ram+0x2012,0);
    let pci=alloc(272);
    expect(cfg_reg(s,pci,64,2,0)==1 && !load64(q+40) && !load64(q+48) && !vp_u16(ram+0x3002) && kvm_u32(ram+0x3040)==24 && kvm_u32(ram+0x5000)==0x1200 && !load64(s+88));
    vp_put16(ram+0x2002,9);expect(reg(s,64,2,0)<0 && !load64(q+40)); // overrun
    kvm_put32(s+512,3);expect(reg(s,84,1,1)==1 && kvm_u32(s+512)==2 && reg(s,88,4,0)<0);
    expect(cfg_reg(s,pci,84,4,2)==1 && !kvm_u32(s+512) && cfg_reg(s,pci,88,4,0)<0);
    // Reset releases resources and disables queues, retaining only private
    // scratch allocations until the device itself is closed.
    expect(cfg_reg(s,pci,20,1,0)==1 && !vg_find(s,77) && !load64(s+8320) && !load64(q+8));
    expect(load64(s+49152) && load64(s+49160));vg_close(s);expect(!load64(s+49152) && !load64(s+49160));
    syscall(11,data,8,0,0,0,0);syscall(11,pci,272,0,0,0,0);return 0;
}
fn main() {
    let s=alloc(65536);let ram=alloc(65536);let request=alloc(1024);let output=alloc(4096);let frame=alloc(3145728);expect(vg_init(s,ram,65536)==1);
    expect(load64(s+40)==0x100000000 && kvm_u32(s+512+8)==1 && !kvm_u32(s+512+12));
    header(request,0x100);kvm_put32(request+4,1);store64(request+8,0xfedcba9876543210);
    expect(vg_command(s,request,24,output,408,0)==408 && kvm_u32(output)==0x1101 && kvm_u32(output+4)==1 && load64(output+8)==0xfedcba9876543210);
    expect(kvm_u32(output+32)==1024 && kvm_u32(output+36)==768 && kvm_u32(output+40)==1 && !load64(output+48));
    expect(vg_command(s,request,24,output,407,0)<0);
    expect(create(s,request,output,1,2,2,2)==0x1100 && create(s,request,output,1,2,2,2)==0x1205);
    expect(create(s,request,output,2,99,2,2)==0x1205 && create(s,request,output,2,2,8192,8192)==0x1201 && !vg_find(s,2));
    // Three backing segments split a pixel in half. Transfers must concatenate
    // them logically, retain row stride and leave all guest bytes untouched.
    kvm_put32(ram+0x1000,0x00ff0000);kvm_put32(ram+0x1004,0x0000ff00);kvm_put32(ram+0x1008,0x000000ff);kvm_put32(ram+0x100c,0x00ffffff);
    vg_copy(ram+0x2000,ram+0x1000,5);vg_copy(ram+0x3000,ram+0x1005,5);vg_copy(ram+0x4000,ram+0x100a,6);
    header(request,0x106);kvm_put32(request+24,1);kvm_put32(request+28,3);
    store64(request+32,0x2000);kvm_put32(request+40,5);store64(request+48,0x3000);kvm_put32(request+56,5);store64(request+64,0x4000);kvm_put32(request+72,6);
    expect(command(s,request,80,output)==0x1100 && command(s,request,80,output)==0x1205);
    header(request,0x105);rect(request,0,0,2,2);kvm_put32(request+48,1);expect(command(s,request,56,output)==0x1100);
    let r=vg_find(s,1);expect(load64(load64(r+32))==load64(ram+0x1000) && load64(load64(r+32)+8)==load64(ram+0x1008));
    // Invalid source bounds fail before partially overwriting the host image.
    store64(request+40,1);expect(command(s,request,56,output)==0x1205 && load64(load64(r+32))==load64(ram+0x1000));
    store64(request+40,-1);expect(command(s,request,56,output)==0x1205);store64(request+40,4);rect(request,0,0,1,2);expect(command(s,request,56,output)==0x1100);
    expect(kvm_u32(load64(r+32))==0x0000ff00 && kvm_u32(load64(r+32)+8)==0x00ffffff);
    // Restore full image and select its 2x2 rectangle; other display pixels
    // stay black. BGRX resource bytes become RGBA host pixels.
    store64(request+40,0);rect(request,0,0,2,2);expect(command(s,request,56,output)==0x1100);
    header(request,0x103);rect(request,0,0,2,2);kvm_put32(request+44,1);expect(command(s,request,48,output)==0x1100);
    expect(vg_frame(s,frame,4096,3145728)==1 && kvm_u32(frame)==0xff0000ff && kvm_u32(frame+4)==0xff00ff00 && kvm_u32(frame+4096)==0xffff0000 && kvm_u32(frame+4100)==0xffffffff && kvm_u32(frame+8)==0xff000000);
    kvm_put32(request+40,1);expect(command(s,request,48,output)==0x1202 && load64(s+8192)==1);kvm_put32(request+40,0);rect(request,1,1,2,2);expect(command(s,request,48,output)==0x1205);
    // Cursor movement redraws from the unmodified resource. Test an opaque
    // red cursor, clipping at a negative hot-spot origin, hide and disable.
    expect(create(s,request,output,2,1,64,64)==0x1100);let cursor=vg_find(s,2);kvm_put32(load64(cursor+32),0xffff0000);
    header(request,0x300);kvm_put32(request+28,1);kvm_put32(request+32,1);kvm_put32(request+40,2);expect(vg_command(s,request,56,0,0,1)==0);
    expect(vg_frame(s,frame,4096,3145728)==1 && kvm_u32(frame+4100)==0xff0000ff && kvm_u32(load64(r+32)+12)==0x00ffffff);
    header(request,0x301);kvm_put32(request+28,2);kvm_put32(request+32,1);expect(vg_command(s,request,56,0,0,1)==0);expect(vg_frame(s,frame,4096,3145728)==1 && kvm_u32(frame+4100)==0xffffffff && kvm_u32(frame+4104)==0xff0000ff);
    header(request,0x300);kvm_put32(request+40,2);kvm_put32(request+44,63);kvm_put32(request+48,63);expect(vg_command(s,request,56,0,0,1)==0 && vg_frame(s,frame,4096,3145728)==1 && kvm_u32(frame)==0xff0000ff);
    kvm_put32(request+40,0);expect(vg_command(s,request,56,0,0,1)==0 && !load64(s+8256));
    header(request,0x107);kvm_put32(request+24,1);expect(command(s,request,32,output)==0x1100 && !load64(r+48));
    header(request,0x105);rect(request,0,0,2,2);kvm_put32(request+48,1);expect(command(s,request,56,output)==0x1205);
    header(request,0x102);kvm_put32(request+24,1);expect(command(s,request,32,output)==0x1100 && !vg_find(s,1) && !load64(s+8192));
    header(request,0x200);expect(command(s,request,24,output)==0x1200);expect(vg_command(s,request,23,output,408,0)<0 && vg_command(s,request,24,output,23,0)<0);
    vg_clear(s);expect(!load64(s+8320));let i=1;while i<=256 {expect(create(s,request,output,i,67,1,1)==0x1100);i=i+1;}expect(create(s,request,output,257,67,1,1)==0x1201);vg_clear(s);expect(!load64(s+8320));
    transport(s,ram,request,output);
    syscall(1,1,"PASS: virtio-gpu resources, pixels, split queues and DMA bounds\n",64,0,0,0);return 0;
}
