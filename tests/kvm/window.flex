import "../../lib/pc-window.flex";
import "../../lib/softvm.flex";
fn expect(v) {if !v {syscall(1,2,"Window assertion failed\n",24,0,0,0);syscall(60,1,0,0,0,0,0);}return 0;}
fn main(argc,argv) {
    let v=softvm_create(134217728);expect(v);let ram=load64(v+24);let ps2=alloc(512);pc_ps2_init(ps2);pc_ps2_command(ps2,0x60);pc_ps2_data(ps2,7);
    expect(pc_window_code(4)==0x1c && pc_window_code(29)==0x1a && pc_window_code(30)==0x16 && pc_window_code(39)==0x45);
    expect(pc_window_code(40)==0x5a && pc_window_code(41)==0x76 && pc_window_code(58)==5 && pc_window_code(69)==7 && pc_window_code(82)==0x175);
    expect(pc_window_key(ps2,4,1) && pc_ps2_read(ps2)==0x1c && pc_window_key(ps2,4,0) && pc_ps2_read(ps2)==0xf0 && pc_ps2_read(ps2)==0x1c);
    expect(pc_window_key(ps2,228,1) && pc_ps2_read(ps2)==0xe0 && pc_ps2_read(ps2)==0x14);
    // A synthetic machine-code guest fills three framebuffer bands with REP STOS.
    // This verifies display plumbing only; it is not Linux or installer evidence.
    let p=ram+0x1000;store8(p,0xbf);kvm_put32(p+1,lnx_fb_usable(134217728));let at=5;let band=0;
    while band<3 {store8(p+at,0xb9);kvm_put32(p+at+1,262144);store8(p+at+5,0xb8);let color=0x2020e0;if band==1 {color=0x20c020;}if band==2 {color=0xe04020;}kvm_put32(p+at+6,color);store8(p+at+10,0xf3);store8(p+at+11,0xab);at=at+12;band=band+1;}store8(p+at,0xf4);
    expect(softvm_start(v,0x1000,32,0,0) && softvm_run(v,1000000)==5);
    let s=pc_window_open(ram,134217728,ps2);if !s {if pc_window_error {let n=0;while load8(pc_window_error+n) {n=n+1;}syscall(1,2,pc_window_error,n,0,0,0);}return 1;}
    gui_title(load64(s),"Flexvirt display test - synthetic guest");
    expect(pc_window_draw(s));let width=gui_pixel_width(load64(s));let height=gui_pixel_height(load64(s));let bytes=width*height*4;let pixels=alloc(bytes);
    expect(gui_read_pixels(load64(s),pixels,width*4,bytes));
    expect((kvm_u32(pixels)&0xffffff)==0x2020e0 && (kvm_u32(pixels+(height/2)*width*4)&0xffffff)==0x20c020 && (kvm_u32(pixels+bytes-4)&0xffffff)==0xe04020);
    expect(load8(pixels+3)==255 && load8(ram+lnx_fb_usable(134217728)+3)==0);
    let frames=1;if argc>1 {frames=600;}let running=1;while frames && running {expect(gui_present(load64(s)));let result=pc_window_tick(s);expect(result>=0);running=result;gui_delay(16);frames=frames-1;}
    pc_window_close(s);gui_quit();softvm_close(v);syscall(11,pixels,bytes,0,0,0,0);syscall(11,ps2,512,0,0,0,0);syscall(1,1,"PASS: guest framebuffer pixels and PS/2 input mapping\n",53,0,0,0);return 0;
}
