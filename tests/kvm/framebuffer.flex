import "../../emulator/linux/framebuffer.flex";
import "../../emulator/backends/software.flex";
fn expect(v) {if !v {syscall(1,2,"Framebuffer assertion failed\n",29,0,0,0);syscall(60,1,0,0,0,0,0);}return 0;}
fn main() {
    expect(!lnx_fb_usable(67108864) && lnx_fb_usable(134217728)==130023424);
    let image=alloc(4096);let rd=alloc(64);
    store8(image+0x1f1,4);store8(image+0x1fe,0x55);store8(image+0x1ff,0xaa);store8(image+0x201,0x6a);
    kvm_put32(image+0x202,0x53726448);store8(image+0x206,15);store8(image+0x207,2);store8(image+0x211,1);store8(image+0x234,1);store8(image+0x236,1);
    kvm_put32(image+0x1f4,64);kvm_put32(image+0x230,0x200000);kvm_put32(image+0x238,2048);kvm_put32(image+0x260,0x200000);kvm_put32(image+0x22c,0x3fffffff);
    let engine=0;while engine<2 {
        let v=softvm_create(134217728);expect(v);let ram=load64(v+24);let cpu=load64(v+64);let run=load64(v+40);let usable=lnx_fb_usable(134217728);
        expect(lnx_load(ram,usable,image,3584,rd,64,"console=tty0")==0x7000);let bp=ram+0x90000;
        expect(kvm_u32(bp+0x218)+64<=usable);expect(lnx_fb_setup(ram,134217728)==ram+usable);
        expect(load8(bp+0x1e8)==4 && load64(bp+0x2d0+48)==usable-1048576);
        expect(load64(bp+0x2d0+60)==usable && load64(bp+0x2d0+68)==4194304 && kvm_u32(bp+0x2d0+76)==2);
        expect(load8(bp+15)==0x23 && lnx_u16(bp+0x12)==1024 && lnx_u16(bp+0x14)==768 && lnx_u16(bp+0x16)==32);
        expect(kvm_u32(bp+0x18)==usable && kvm_u32(bp+0x1c)*65536==4194304 && lnx_u16(bp+0x24)==4096);
        expect(load8(bp+0x26)==8 && load8(bp+0x27)==0 && load8(bp+0x29)==8 && load8(bp+0x2b)==16 && !load8(bp+0x2c));
        // The actual CPU writes pixels through checked guest physical memory.
        let code=ram+0x1000;store8(code,0xc7);store8(code+1,5);kvm_put32(code+2,usable);kvm_put32(code+6,0xff332211);store8(code+10,0xf4);
        x86_jit_enabled=engine;x86_jit_min_fuel=0;x86_jit_threshold=1;expect(softvm_start(v,0x1000,32,0,0));expect(softvm_run(v,100)==5 && kvm_u32(ram+usable)==0xff332211);
        expect(!lnx_fb_setup(ram,134217728));softvm_close(v);engine=engine+1;
    }
    syscall(11,image,4096,0,0,0,0);syscall(11,rd,64,0,0,0,0);return 0;
}
