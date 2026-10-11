import "../../lib/kvm-boot.flex";
fn expect(condition) {if !condition {syscall(1,2,"KVM offline assertion failed\n",29,0,0,0);syscall(60,1,0,0,0,0,0);}return 0;}
fn main() {
    let ram=alloc(67108864);let image=alloc(4096);expect(ram>0 && image>0);
    // Independent flat header: 32-byte header at file offset 16, code at 64.
    let h=image+16;kvm_put32(h,0x1badb002);kvm_put32(h+4,0x10003);kvm_put32(h+8,-(0x1badb002+0x10003));
    kvm_put32(h+12,0x400010);kvm_put32(h+16,0x400000);kvm_put32(h+20,0x400080);kvm_put32(h+24,0x400100);kvm_put32(h+28,0x400040);
    store8(image+64,0xf4);store8(ram+0x400080,0xaa);
    expect(kvm_multiboot(0,67108864,image,128)==0x400040);
    expect(kvm_multiboot(ram,67108864,image,128)==0x400040);
    expect(load8(ram+0x400040)==0xf4 && load8(ram+0x400080)==0);
    expect(kvm_u32(ram+0x8000)==0x41 && kvm_u32(ram+0x8008)==64512);
    expect(kvm_u32(ram+0x802c)==48 && kvm_u32(ram+0x8030)==0x9000);
    expect(load64(ram+0x901c)==1048576 && load64(ram+0x9024)==66060288);
    store8(ram+0x400000,0x55);
    kvm_put32(h+24,0xffffffff);expect(!kvm_multiboot(ram,67108864,image,128));expect(load8(ram+0x400000)==0x55);
    kvm_put32(h+24,0x400100);kvm_put32(h+28,0x500000);expect(!kvm_multiboot(ram,67108864,image,128));
    kvm_put32(h+28,0x400040);expect(!kvm_multiboot(ram,67108864,image,127));expect(!kvm_multiboot(ram,33554432,image,128));
    kvm_put32(h+8,0);expect(!kvm_multiboot(ram,67108864,image,128));expect(!kvm_multiboot(ram,67108864,image,16));
    kvm_put32(h+4,0x10007);kvm_put32(h+8,-(0x1badb002+0x10007));expect(!kvm_multiboot(ram,67108864,image,128));
    // Adversarial exit metadata must never produce an out-of-mapping pointer.
    let v=alloc(64);let run=alloc(4096);store64(v+40,run);store64(v+48,4096);
    kvm_put32(run+8,2);store8(run+32,1);store8(run+33,1);kvm_put32(run+36,3);store64(run+40,128);
    expect(kvm_io_data(v)==run+128);
    store64(run+40,4095);expect(!kvm_io_data(v));store64(run+40,-1);expect(!kvm_io_data(v));
    store64(run+40,128);kvm_put32(run+36,0xffffffff);expect(!kvm_io_data(v));
    kvm_put32(run+36,3);store8(run+33,8);expect(!kvm_io_data(v));store8(run+33,1);store8(run+32,2);expect(!kvm_io_data(v));
    store8(run+32,1);kvm_put32(run+8,5);expect(!kvm_io_data(v));
    expect(!kvm_create(1) && kvm_error==-22);expect(!kvm_create(3221229568) && kvm_error==-22);
    syscall(11,run,4096,0,0,0,0);syscall(11,v,64,0,0,0,0);syscall(11,image,4096,0,0,0,0);syscall(11,ram,67108864,0,0,0,0);
    return 0;
}
