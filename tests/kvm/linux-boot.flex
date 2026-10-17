import "../../emulator/linux/boot.flex";
import "../../emulator/backends/software.flex";
fn expect(condition) {if !condition {syscall(1,2,"Linux boot assertion failed\n",28,0,0,0);syscall(60,1,0,0,0,0,0);}return 0;}
fn main(argc,argv) {
    let image=alloc(4096);let initrd=alloc(64);store8(initrd,0xab);store8(initrd+63,0xcd);
    store8(image+0x1f1,4);store8(image+0x1fe,0x55);store8(image+0x1ff,0xaa);store8(image+0x201,0x6a);
    kvm_put32(image+0x202,0x53726448);store8(image+0x206,15);store8(image+0x207,2);store8(image+0x211,1);store8(image+0x234,1);store8(image+0x236,1);
    kvm_put32(image+0x1f4,64);kvm_put32(image+0x230,0x200000);kvm_put32(image+0x238,2048);kvm_put32(image+0x260,0x200000);kvm_put32(image+0x22c,0x3fffffff);
    store8(image+2560+512,0xf4);
    if argc==2 {
        // Monitor fixture: enable interrupts, halt with the PIC masked, then
        // UD2. Correct idle handling must time out without reaching UD2.
        store8(image+3072,0xfb);store8(image+3073,0xf4);store8(image+3074,0x0f);store8(image+3075,0x0b);
        let fd=syscall(2,load64(argv+8),0x241,384,0,0,0);expect(fd>=0);expect(syscall(1,fd,image,3584,0,0,0)==3584);syscall(3,fd,0,0,0,0,0);return 0;
    }
    expect(lnx_load(0,67108864,image,3584,initrd,64,"console=ttyS0")==0x7000);
    expect(!lnx_load(0,67108864,image,3583,initrd,64,"console=ttyS0"));
    store8(image+0x234,0);expect(!lnx_load(0,67108864,image,3584,initrd,64,""));store8(image+0x234,1);
    kvm_put32(image+0x260,0xffffffff);expect(!lnx_load(0,67108864,image,3584,initrd,64,""));kvm_put32(image+0x260,0x200000);
    kvm_put32(image+0x238,2);expect(!lnx_load(0,67108864,image,3584,initrd,64,"long"));kvm_put32(image+0x238,2048);
    kvm_put32(image+0x22c,0x100000);expect(!lnx_load(0,67108864,image,3584,initrd,64,""));kvm_put32(image+0x22c,0x3fffffff);
    let elf=alloc(4096);store64(elf,0x00010102464c457f);store8(elf+16,2);store8(elf+18,62);kvm_put32(elf+20,1);
    store64(elf+24,0x1000200);store64(elf+32,64);store8(elf+52,64);store8(elf+54,56);store8(elf+56,1);
    let ph=elf+64;kvm_put32(ph,1);kvm_put32(ph+4,6);store64(ph+8,512);store64(ph+16,0xffffffff81000000);store64(ph+24,0x1000000);store64(ph+32,1024);store64(ph+40,4096);store8(elf+1024,0xf4);
    expect(lnx_elf(0,0x1200000,elf,1536)==0x1000200);
    expect(!lnx_elf(0,0x1200000,elf,1535));
    store64(elf+24,0xffffffff81000200);expect(lnx_elf(0,0x1200000,elf,1536)==0x1000200);store64(elf+24,0x1000200);
    store64(elf+24,0x8000);expect(!lnx_elf(0,0x1200000,elf,1536));store64(elf+24,0x1000200);
    store64(ph+40,0x300000);expect(!lnx_elf(0,0x1200000,elf,1536));store64(ph+40,4096);
    store8(elf+56,2);kvm_copy(ph+56,ph,56);expect(!lnx_elf(0,0x1200000,elf,1536));store8(elf+56,1);
    let backend=0;while backend<2 {
        kvm_emulated_api=backend;let v=0;if backend {v=kvm_create(67108864);}else {v=softvm_create(67108864);}expect(v!=0);
        let ram=load64(v+24);expect(lnx_load(ram,67108864,image,3584,initrd,64,"console=ttyS0")==0x7000);
        let bp=ram+0x90000;expect(kvm_u32(bp+0x228)==0x91000 && load8(ram+0x91000)==99);
        expect(load8(bp+0x1e8)==3 && kvm_u32(bp+0x2d0+16)==1 && load64(bp+0x2d0+28)==0x61000);
        expect(load8(ram+kvm_u32(bp+0x218))==0xab && load8(ram+kvm_u32(bp+0x218)+63)==0xcd && kvm_u32(bp+0x21c)==64);
        let reason=0;let cpu=0;
        if backend {expect(kvm_start(v,0x7000,32,0,0));reason=kvm_run(v);cpu=kvme_cpu;}else {expect(softvm_start(v,0x7000,32,0,0));reason=softvm_run(v,100000);cpu=load64(v+64);}
        expect(reason==5 && load64(cpu+144)==64 && load64(cpu+48)==0x90000 && load64(cpu+128)==0x1000201);
        expect((load64(cpu+152)&0x80000000)!=0 && (load64(cpu+168)&32)!=0 && (load64(cpu+176)&0x500)==0x500);
        expect(lnx_load_target(ram,67108864,image,3584,initrd,64,"console=ttyS0",0x1000200)==0x7000);
        store8(ram+0x1000000,0xaa);store8(elf+56,2);expect(!lnx_elf(ram,0x1200000,elf,1536) && load8(ram+0x1000000)==0xaa);store8(elf+56,1);
        expect(lnx_elf(ram,0x1200000,elf,1536)==0x1000200 && !load8(ram+0x1000fff));
        if backend {expect(kvm_start(v,0x7000,32,0,0));expect(kvm_run(v)==5);}else {expect(softvm_start(v,0x7000,32,0,0));expect(softvm_run(v,100000)==5);}
        expect(load64(cpu+128)==0x1000201 && load64(cpu+144)==64);
        if backend {kvm_close(v);}else {softvm_close(v);}
        // RAM above the trampoline's 1-GiB identity map is advertised by E820;
        // boot payloads, including the initramfs, still fit the low map/limit.
        if backend {v=kvm_create(2147483648);}else {v=softvm_create(2147483648);}expect(v!=0);ram=load64(v+24);
        expect(lnx_load(ram,2147483648,image,3584,initrd,64,"console=ttyS0")==0x7000);bp=ram+0x90000;
        expect(load64(bp+0x2d0+48)==2147483648-1048576 && kvm_u32(bp+0x218)<1073741824 && load8(ram+kvm_u32(bp+0x218))==0xab);
        if backend {expect(kvm_start(v,0x7000,32,0,0));expect(kvm_run(v)==5);kvm_close(v);}else {expect(softvm_start(v,0x7000,32,0,0));expect(softvm_run(v,100000)==5);softvm_close(v);}
        backend=backend+1;
    }
    syscall(11,elf,4096,0,0,0,0);kvm_emulated_api=0;syscall(11,image,4096,0,0,0,0);syscall(11,initrd,64,0,0,0,0);return 0;
}
