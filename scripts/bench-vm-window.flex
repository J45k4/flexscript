import "../emulator/pc/window.flex";
// Isolated display benchmark: three 100-frame runs, each reporting wall and
// process CPU nanoseconds on separate lines. --changing forces composition on
// every frame; otherwise the image is stable. Does not measure guest CPU speed.
fn expect(v) {if !v {syscall(60,1,0,0,0,0,0);}return 0;}
fn number(n) {let p=alloc(32);let i=31;store8(p+i,10);while n || i==31 {i=i-1;store8(p+i,48+n%10);n=n/10;}syscall(1,1,p+i,32-i,0,0,0);syscall(11,p,32,0,0,0,0);return 0;}
fn time(p,clock) {expect(syscall(228,clock,p,0,0,0,0)==0);return load64(p)*1000000000+load64(p+8);}
fn main(argc,argv) {
 expect(argc==1 || argc==2);let changing=argc==2;
 if changing {let arg=load64(argv+8);let wanted="--changing";let i=0;while load8(wanted+i) {expect(load8(arg+i)==load8(wanted+i));i=i+1;}expect(!load8(arg+i));}
 let ram=alloc(134217728);let ps2=alloc(512);pc_ps2_init(ps2);let gpu=alloc(65536);expect(vg_init(gpu,ram,134217728)==1);let request=alloc(64);let response=alloc(408);
 kvm_put32(request,0x101);kvm_put32(request+24,1);kvm_put32(request+28,2);kvm_put32(request+32,1024);kvm_put32(request+36,768);expect(vg_command(gpu,request,40,response,408,0)==24 && kvm_u32(response)==0x1100);
 kvm_zero(request,64);kvm_put32(request,0x103);kvm_put32(request+32,1024);kvm_put32(request+36,768);kvm_put32(request+44,1);expect(vg_command(gpu,request,48,response,408,0)==24 && kvm_u32(response)==0x1100);
 let s=pc_window_open(ram,134217728,ps2);expect(s);store64(s+96,gpu);expect(pc_window_draw(s) && gui_present(load64(s)));let stamp=alloc(16);
 let repeat=0;while repeat<3 {let start=time(stamp,1);let cpu=time(stamp,2);let i=0;while i<100 {if changing {store64(gpu+8240,load64(gpu+8240)+1);}expect(pc_window_draw(s) && gui_present(load64(s)));i=i+1;}number(time(stamp,1)-start);number(time(stamp,2)-cpu);repeat=repeat+1;}
 pc_window_close(s);vg_close(gpu);gui_quit();return 0;
}
