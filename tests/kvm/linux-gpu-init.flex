// Minimal initramfs PID 1 for checking the official ISO's Linux GPU modules.
// Supply /virtio_dma_buf.ko and /virtio-gpu.ko from the matching ISO kernel.
// This driver diagnostic does not install or replace the Omarchy live system.
fn length(s) {let n=0;while load8(s+n) {n=n+1;}return n;}
fn print(s) {syscall(1,1,s,length(s),0,0,0);return 0;}
fn number(n) {let p=alloc(32);let i=31;store8(p+i,10);if n<0 {print("-");n=-n;}while n || i==31 {i=i-1;store8(p+i,48+n%10);n=n/10;}syscall(1,1,p+i,32-i,0,0,0);return 0;}
fn stop() {while 1 {syscall(34,0,0,0,0,0,0);}return 0;}
fn check(code) {if code<0 {print("FAIL: Linux GPU diagnostic syscall ");number(code);stop();}return code;}
fn module(path) {print("Loading ");print(path);print("\n");let fd=check(syscall(2,path,0,0,0,0,0));let result=syscall(313,fd,"",0,0,0,0);syscall(3,fd,0,0,0,0,0);return check(result);}
fn u32(p) {return load64(p)&0xffffffff;}
fn u16(p) {return load8(p)|(load8(p+1)<<8);}
fn put32(p,value) {let i=0;while i<4 {store8(p+i,value>>(i*8));i=i+1;}return 0;}
fn expect(ok,text) {if !ok {print("FAIL: ");print(text);print("\n");stop();}return 0;}
fn ioctl(fd,request,arg) {return check(syscall(16,fd,request,arg,0,0,0));}
fn scanout(fd,render,info) {
    print("Querying DRM connector mode and PRIME capability\n");
    let cap=alloc(16);store64(cap,5);ioctl(fd,0xc010640c,cap);expect((load64(cap+8)&3)==3,"PRIME import/export capability");
    let ids=alloc(8);store64(info+8,ids);store64(info+16,ids+4);put32(info+32,0);put32(info+44,0);ioctl(fd,0xc04064a0,info);
    let crtc=u32(ids);let connector=u32(ids+4);expect(crtc && connector,"DRM object IDs");
    let conn=alloc(80);put32(conn+48,connector);ioctl(fd,0xc05064a7,conn);let count=u32(conn+32);expect(count>0 && count<=64,"bounded connector modes");
    let modes=alloc(count*68);store64(conn+8,modes);put32(conn+36,0);put32(conn+40,0);ioctl(fd,0xc05064a7,conn);expect(u32(conn+32)<=count,"stable connector modes");
    let mode=0;let i=0;while i<u32(conn+32) {let p=modes+i*68;if u16(p+4)==1024 && u16(p+14)==768 {mode=p;}i=i+1;}expect(mode,"1024x768 connector mode");
    print("Allocating and mapping a Linux DRM dumb buffer\n");
    let dumb=alloc(32);put32(dumb,768);put32(dumb+4,1024);put32(dumb+8,32);ioctl(fd,0xc02064b2,dumb);
    let handle=u32(dumb+16);let pitch=u32(dumb+20);let bytes=load64(dumb+24);expect(handle && pitch>=4096 && pitch<=1048576 && bytes>=pitch*768 && bytes<=33554432,"dumb buffer geometry");
    let map=alloc(16);put32(map,handle);ioctl(fd,0xc01064b3,map);let pixels=check(syscall(9,0,bytes,3,1,fd,load64(map+8)));
    let y=0;while y<768 {let x=0;while x<1024 {let color=0x00ff0000;if x>=512 {color=0x0000ff00;}if y>=384 {color=0x000000ff;if x>=512 {color=0x00ffffff;}}store64(pixels+y*pitch+x*4,color|(color<<32));x=x+2;}y=y+1;}
    print("Exporting and importing the buffer through PRIME\n");
    let prime=alloc(16);put32(prime,handle);put32(prime+4,0x80002);ioctl(fd,0xc00c642d,prime);let dma=u32(prime+8);expect(dma<1048576,"PRIME dma-buf descriptor");
    let imported=alloc(16);put32(imported+8,dma);ioctl(render,0xc00c642e,imported);expect(u32(imported),"render-node PRIME import handle");
    let close=alloc(8);put32(close,u32(imported));ioctl(render,0x40086409,close);check(syscall(3,dma,0,0,0,0,0));
    print("Adding an XRGB8888 framebuffer and selecting scanout\n");
    let fb=alloc(104);put32(fb+4,1024);put32(fb+8,768);put32(fb+12,0x34325258);put32(fb+20,handle);put32(fb+36,pitch);ioctl(fd,0xc06864b8,fb);expect(u32(fb),"DRM framebuffer ID");
    let set=alloc(104);store64(set,ids+4);put32(set+8,1);put32(set+12,crtc);put32(set+16,u32(fb));put32(set+32,1);i=0;while i<68 {store8(set+36+i,load8(mode+i));i=i+1;}ioctl(fd,0xc06864a2,set);
    print("Flushing the framebuffer and verifying the active CRTC\n");
    let dirty=alloc(24);put32(dirty,u32(fb));ioctl(fd,0xc01864b1,dirty);
    let current=alloc(104);put32(current+12,crtc);ioctl(fd,0xc06864a1,current);expect(u32(current+16)==u32(fb) && u32(current+32) && u16(current+40)==1024 && u16(current+50)==768,"active DRM scanout state");
    print("PASS: Linux DRM dumb-buffer mmap, PRIME export/import, modeset and dirty flush\n");return 0;
}
fn main() {
    print("Linux GPU diagnostic init started\n");
    print("Mounting devtmpfs\n");
    check(syscall(165,"devtmpfs","/dev","devtmpfs",0,"",0));
    print("Mounting sysfs\n");
    check(syscall(165,"sysfs","/sys","sysfs",0,"",0));
    module("/virtio_dma_buf.ko");module("/virtio-gpu.ko");
    // Query the DRM driver itself: the sysfs device/driver symlink names its
    // PCI parent transport (virtio-pci), not the virtio GPU child driver.
    let info=alloc(64);let version=alloc(64);let name=alloc(64);let fd=-1;let match=0;let index=0;
    while index<2 && !match {
        let path="/dev/dri/card0";if index {path="/dev/dri/card1";}fd=syscall(2,path,2,0,0,0,0);
        if fd>=0 {store64(version+16,64);store64(version+24,name);check(syscall(16,fd,0xc0406400,version,0,0,0));
            let n=load64(version+16);if n>64 {n=64;}print("DRM driver: ");syscall(1,1,name,n,0,0,0);print("\n");
            if n==10 {let j=0;while j<10 && load8(name+j)==load8("virtio_gpu"+j) {j=j+1;}match=j==10;}
            if !match {syscall(3,fd,0,0,0,0,0);fd=-1;}
        }index=index+1;
    }
    if !match {print("FAIL: DRM card is not bound to virtio_gpu\n");stop();}
    check(syscall(16,fd,0xc04064a0,info,0,0,0));
    if (load64(info+32)>>32)!=1 || (load64(info+40)&0xffffffff)!=1 {print("FAIL: unexpected Linux DRM scanout topology\n");stop();}
    print("Opening render node\n");let render=check(syscall(2,"/dev/dri/renderD128",2,0,0,0,0));
    print("PASS: official Linux virtio_gpu driver, DRM scanout and render node\n");scanout(fd,render,info);return stop();
}
