import "../../lib/pc-virtio-gpu-state.flex";
global stage=0;
fn expect(ok) {if !ok {syscall(1,2,"GPU state assertion failed\n",27,0,0,0);let p=alloc(8);store8(p,48+stage);store8(p+1,10);syscall(1,2,p,2,0,0,0);syscall(60,1,0,0,0,0,0);}return 0;}
fn header(p,kind) {kvm_zero(p,1024);kvm_put32(p,kind);return 0;}
fn command(s,p,n,out) {expect(vg_command(s,p,n,out,408,0)>0);return kvm_u32(out);}
fn create(s,p,out,id,w,h) {header(p,0x101);kvm_put32(p+24,id);kvm_put32(p+28,2);kvm_put32(p+32,w);kvm_put32(p+36,h);expect(command(s,p,40,out)==0x1100);return 0;}
fn transfer(s,p,out) {header(p,0x105);kvm_put32(p+32,2);kvm_put32(p+36,2);kvm_put32(p+48,1);expect(command(s,p,56,out)==0x1100);return 0;}
fn rejected(target,data,bytes) {let old=vg_find(target,99);expect(old && vgs_load(target,data,bytes)<0 && vg_find(target,99)==old && !vg_find(target,1));return 0;}
fn main() {
    let s=alloc(65536);let target=alloc(65536);let ram=alloc(65536);let other=alloc(65536);let p=alloc(1024);let out=alloc(4096);let stream=alloc(65536);
    expect(vg_init(s,ram,65536)==1 && vg_init(target,other,65536)==1);create(s,p,out,1,2,2);create(s,p,out,2,64,64);create(target,p,out,99,1,1);
    let r=vg_find(s,1);let cursor=vg_find(s,2);kvm_put32(load64(cursor+32),0xff112233);
    store64(ram+0x1000,0x0000ff0000ff0000);store64(ram+0x2000,0x00ffffff000000ff);
    header(p,0x106);kvm_put32(p+24,1);kvm_put32(p+28,2);store64(p+32,0x1000);kvm_put32(p+40,8);store64(p+48,0x2000);kvm_put32(p+56,8);expect(command(s,p,64,out)==0x1100);transfer(s,p,out);
    header(p,0x103);kvm_put32(p+32,2);kvm_put32(p+36,2);kvm_put32(p+44,1);expect(command(s,p,48,out)==0x1100);
    header(p,0x300);kvm_put32(p+28,1);kvm_put32(p+32,1);kvm_put32(p+40,2);expect(vg_command(s,p,56,0,0,1)==0);
    // Preserve an active transport, IRQ edge state and wrapping counters.
    store64(s+24,5);store8(s+260,5);store64(s+48,0x100000000);store64(s+72,15);store64(s+88,1);
    let q=vp_queue(s,0);store64(q+8,1);store64(q+16,0xa000);store64(q+24,0xb000);store64(q+32,0xc000);store64(q+40,65535);store64(q+48,65535);
    stage=1;let bytes=vgs_size(s);expect(bytes<65536 && vgs_encode(s,stream,bytes-1)<0 && vgs_encode(s,stream,65536)==bytes);
    expect(!load64(stream+64) && load64(stream+24)==65536 && load64(stream+16)==2 && load64(stream+8512+32)==16 && load64(stream+8512+40)==2);
    stage=2;rejected(target,stream,8511);rejected(target,stream,bytes-1);let value=load64(stream+16);store64(stream+16,-1);rejected(target,stream,bytes);store64(stream+16,value);
    value=load64(stream+8);store64(stream+8,value+1);rejected(target,stream,bytes);store64(stream+8,value);
    store64(stream+64,ram);rejected(target,stream,bytes);store64(stream+64,0);
    value=load64(stream+8512+16);store64(stream+8512+16,8193);rejected(target,stream,bytes);store64(stream+8512+16,value);
    value=load64(stream+8512+64);store64(stream+8512+64,65535);rejected(target,stream,bytes);store64(stream+8512+64,value);
    let second=8512+64+32+16;value=load64(stream+second);store64(stream+second,1);rejected(target,stream,bytes);store64(stream+second,value);
    value=load64(stream+64+1024+16);store64(stream+64+1024+16,65535);rejected(target,stream,bytes);store64(stream+64+1024+16,value);
    value=load64(stream+8256);store64(stream+8256,123);rejected(target,stream,bytes);store64(stream+8256,value);
    stage=3;let a=alloc(3145728);let b=alloc(3145728);expect(vg_frame(s,a,4096,3145728)==1 && vgs_load(target,stream,bytes)==1);
    expect(!vg_find(target,99) && vg_find(target,1) && vg_find(target,2) && load64(target)==other && load64(vg_find(target,1)+32)!=load64(r+32) && load64(vg_find(target,1)+48)!=load64(r+48));
    expect(vg_frame(target,b,4096,3145728)==1);let i=0;while i<3145728 {expect(load64(a+i)==load64(b+i));i=i+8;}
    expect(vp_irq(s) && vp_irq(target) && !vp_irq(s) && !vp_irq(target) && load64(vp_queue(target,0)+40)==65535 && load64(vp_queue(target,0)+48)==65535);
    // The restored backing list refers to GPAs in the new RAM, never the
    // source device's allocations or original guest memory.
    store64(other+0x1000,0x00ffffff00ffffff);store64(other+0x2000,0x00ffffff00ffffff);transfer(target,p,out);expect(kvm_u32(load64(vg_find(target,1)+32))==0xffffff && kvm_u32(load64(r+32))==0xff0000);
    expect(vgs_encode(target,stream,65536)==bytes && vgs_load(target,stream,bytes)==1);
    vg_close(s);vg_close(target);syscall(1,1,"PASS: GPU state pixels, cursor, queues, fresh pointers and atomic rejection\n",76,0,0,0);return 0;
}
