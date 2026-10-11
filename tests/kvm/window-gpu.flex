import "../../lib/pc-window.flex";
import "../../lib/pc-virtio-gpu-state.flex";
fn expect(v) {if !v {syscall(1,2,"GPU window assertion failed\n",28,0,0,0);syscall(60,1,0,0,0,0,0);}return 0;}
fn command(g,p,n,out) {expect(vg_command(g,p,n,out,408,0)==24 && kvm_u32(out)==0x1100);return 0;}
fn header(p,type) {kvm_zero(p,64);kvm_put32(p,type);return 0;}
fn transfer(g,p,out,id,w,h) {header(p,0x105);kvm_put32(p+32,w);kvm_put32(p+36,h);kvm_put32(p+48,id);command(g,p,56,out);return 0;}
fn flush(g,p,out) {header(p,0x104);kvm_put32(p+32,2);kvm_put32(p+36,2);kvm_put32(p+40,1);command(g,p,48,out);return 0;}
fn resource(g,ram,p,out,id,w,h,color,address) {
    header(p,0x101);kvm_put32(p+24,id);kvm_put32(p+28,2);kvm_put32(p+32,w);kvm_put32(p+36,h);command(g,p,40,out);
    let i=0;while i<w*h {kvm_put32(ram+address+i*4,color);i=i+1;}
    header(p,0x106);kvm_put32(p+24,id);kvm_put32(p+28,1);store64(p+32,address);kvm_put32(p+40,w*h*4);command(g,p,48,out);transfer(g,p,out,id,w,h);return 0;
}
fn primary(g,ram,p,out,color) {
    resource(g,ram,p,out,1,2,2,color,0x2000);header(p,0x103);kvm_put32(p+32,2);kvm_put32(p+36,2);kvm_put32(p+44,1);command(g,p,48,out);flush(g,p,out);return 0;
}
fn pixels(s,frame) {expect(pc_window_draw(s) && gui_read_pixels(load64(s),frame,4096,3145728));return 0;}
fn main() {
    let ram=alloc(134217728);let ps2=alloc(512);pc_ps2_init(ps2);let s=pc_window_open(ram,134217728,ps2);expect(s);
    let gpu=alloc(65536);let other=alloc(65536);expect(vg_init(gpu,ram,134217728)==1 && vg_init(other,ram,134217728)==1);
    let p=alloc(64);let out=alloc(408);let frame=alloc(3145728);store64(s+96,gpu);
    primary(gpu,ram,p,out,0x00ff0000);pixels(s,frame);expect(kvm_u32(frame)==0xff0000ff && kvm_u32(frame+8)==0xff000000);
    let i=0;while i<10 {pixels(s,frame);expect(kvm_u32(frame)==0xff0000ff);i=i+1;}
    // A fresh decoded image can replace pixels without changing its generation.
    primary(other,ram,p,out,0x0000ff00);expect(load64(gpu+8240)==load64(other+8240));let bytes=vgs_size(other);let image=alloc(bytes);
    expect(vgs_encode(other,image,bytes)==bytes && vgs_load(gpu,image,bytes)==1);pixels(s,frame);expect(kvm_u32(frame)==0xff00ff00);
    // TRANSFER updates backing storage; FLUSH publishes the display update.
    i=0;while i<4 {kvm_put32(ram+0x2000+i*4,0x000000ff);i=i+1;}transfer(gpu,p,out,1,2,2);pixels(s,frame);expect(kvm_u32(frame)==0xff00ff00);
    flush(gpu,p,out);pixels(s,frame);expect(kvm_u32(frame)==0xffff0000);
    resource(gpu,ram,p,out,2,64,64,0,0x4000);kvm_put32(ram+0x4000,0xffffffff);transfer(gpu,p,out,2,64,64);
    header(p,0x300);kvm_put32(p+28,1);kvm_put32(p+40,2);expect(vg_command(gpu,p,56,out,408,1)==0);pixels(s,frame);expect(kvm_u32(frame)==0xffff0000 && kvm_u32(frame+4)==0xffffffff);
    header(p,0x301);kvm_put32(p+32,1);expect(vg_command(gpu,p,56,out,408,1)==0);pixels(s,frame);expect(kvm_u32(frame+4)==0xffff0000 && kvm_u32(frame+4096)==0xffffffff);
    vg_clear(gpu);pixels(s,frame);expect(kvm_u32(frame)==0xff000000 && kvm_u32(frame+4096)==0xff000000);
    primary(gpu,ram,p,out,0x00ff0000);pixels(s,frame);expect(kvm_u32(frame)==0xff0000ff);
    pc_window_close(s);vg_close(gpu);vg_close(other);gui_quit();syscall(1,1,"PASS: GPU display refresh, cursor movement, reset and same-generation restoration\n",81,0,0,0);return 0;
}
