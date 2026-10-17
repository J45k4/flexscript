import "../../emulator/pc/rtc.flex";
fn expect(v) {if !v {syscall(60,1,0,0,0,0,0);}return 0;}
fn access(s,r,v,out,t) {let d=alloc(8);store8(d,r);expect(pc_rtc_io(s,0x70,1,1,d,1,t)==1);store8(d,v);let result=pc_rtc_io(s,0x71,1,out,d,1,t);let value=load8(d);syscall(11,d,8,0,0,0,0);if result<0 {return -1;}return value;}
fn main() {
    let s=alloc(256);pc_rtc_init(s);expect(access(s,9,0,0,0)==0x26 && access(s,8,0,0,0)==0x10 && access(s,7,0,0,0)==0x11 && access(s,0x32,0,0,0)==0x20);
    expect(access(s,10,0,0,1192891)&128);expect(!(access(s,10,0,0,1193182)&128));expect(access(s,0,0,0,1193182)==1);
    expect(access(s,12,0,0,1193182)==16);expect(!access(s,12,0,0,1193182));
    // SET freezes updates, switches BCD/binary, and permits setting the calendar.
    access(s,11,0x86,1,1193182);access(s,0,59,1,1193182);access(s,2,59,1,1193182);access(s,4,23,1,1193182);
    access(s,7,28,1,1193182);access(s,8,2,1,1193182);access(s,9,24,1,1193182);expect(access(s,0,0,0,11931820)==59);
    access(s,11,6,1,11931820);expect(access(s,0,0,0,13125002)==0);expect(access(s,7,0,0,13125002)==29 && access(s,8,0,0,13125002)==2);
    // Read-only valid-RAM flag and update IRQ flag clear on read.
    access(s,13,0,1,13125002);expect(access(s,13,0,0,13125002)==128);access(s,11,0x16,1,13125002);
    expect(access(s,12,0,0,14318184)==0x90);expect(!access(s,12,0,0,14318184));
    access(s,11,0x82,1,14318184);expect(access(s,7,0,0,14318184)==0x29);expect(access(s,9,0,0,14318184)==0x24);
    expect(access(s,11,0,1,14318184)==-1);
    pc_rtc_init(s);access(s,11,0x42,1,0);expect(!pc_rtc_irq(s,1165));expect(pc_rtc_irq(s,1166));expect(!pc_rtc_irq(s,2332));
    expect(access(s,12,0,0,2332)==0xc0);expect(pc_rtc_irq(s,3498));expect(access(s,12,0,0,3498)==0xc0);
    access(s,11,2,1,3498);expect(!pc_rtc_irq(s,4664));expect(access(s,12,0,0,4664)==0x40);
    expect(access(s,11,0x22,1,4664)==-1);syscall(11,s,256,0,0,0,0);return 0;
}
