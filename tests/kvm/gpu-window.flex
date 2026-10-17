import "../../emulator/pc/window.flex";
fn expect(v) {if !v {syscall(1,2,"GPU window assertion failed\n",28,0,0,0);syscall(60,1,0,0,0,0,0);}return 0;}
// This SDL readback test uses controlled resource pixels. Linux driver and
// installer verification are separate; it proves the actual upload path.
fn main() {
    let bytes=134217728;let ram=alloc(bytes);let ps2=alloc(512);pc_ps2_init(ps2);
    let gpu=alloc(65536);expect(vg_init(gpu,ram,bytes)==1);
    let window=pc_window_open(ram,bytes,ps2);expect(window);store64(window+96,gpu);
    let pixels=alloc(3145728);let boot=ram+lnx_fb_usable(bytes);kvm_put32(boot,0x00332211);
    expect(pc_window_draw(window) && gui_read_pixels(load64(window),pixels,4096,3145728));expect(kvm_u32(pixels)==0xff332211);
    let request=alloc(64);let response=alloc(24);kvm_put32(request,0x101);kvm_put32(request+24,1);kvm_put32(request+28,2);kvm_put32(request+32,2);kvm_put32(request+36,2);
    expect(vg_command(gpu,request,40,response,24,0)==24 && kvm_u32(response)==0x1100);
    let resource=vg_find(gpu,1);kvm_put32(load64(resource+32),0x00ff0000);kvm_put32(load64(resource+32)+4,0x000000ff);
    kvm_put32(request,0x103);kvm_put32(request+24,0);kvm_put32(request+28,0);kvm_put32(request+32,2);kvm_put32(request+36,2);kvm_put32(request+40,0);kvm_put32(request+44,1);
    expect(vg_command(gpu,request,48,response,24,0)==24 && kvm_u32(response)==0x1100);
    expect(pc_window_draw(window) && gui_read_pixels(load64(window),pixels,4096,3145728));
    expect(kvm_u32(pixels)==0xff0000ff && kvm_u32(pixels+4)==0xffff0000 && kvm_u32(pixels+8)==0xff000000 && kvm_u32(boot)==0x00332211);
    // Disabling an acquired GPU scanout blanks it; stale boot-console pixels
    // must not reappear once Linux has switched display ownership.
    kvm_put32(request+44,0);expect(vg_command(gpu,request,48,response,24,0)==24);
    expect(pc_window_draw(window) && gui_read_pixels(load64(window),pixels,4096,3145728) && kvm_u32(pixels)==0xff000000);
    pc_window_close(window);vg_close(gpu);gui_quit();return 0;
}
