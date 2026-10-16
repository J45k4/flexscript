import "../../emulator/pc/pit.flex";
fn expect(value) {if !value {syscall(60,1,0,0,0,0,0);}return 0;}
fn wr(s,p,v,t) {let d=alloc(8);store8(d,v);let r=pc_pit_io(s,p,1,1,d,1,t);syscall(11,d,8,0,0,0,0);return r;}
fn rd(s,p,t) {let d=alloc(8);expect(pc_pit_io(s,p,1,0,d,1,t)==1);let v=load8(d);syscall(11,d,8,0,0,0,0);return v;}
fn main() {
    let s=alloc(512);pc_pit_init(s);let d=alloc(8);
    expect(!pc_pit_io(s,0x3f8,1,0,d,1,0));expect(!pc_pit_io(s,0x40,2,0,d,1,0));
    // Mode 0, little-endian programming, zero divisor means 65536.
    expect(wr(s,0x43,0xb0,0)==1);expect(wr(s,0x42,0,0)==1);expect(load64(s+256+40)==1);
    wr(s,0x42,0,0);expect(load64(s+256)==65536 && !load64(s+256+40));
    wr(s,0x61,1,0);expect(!(rd(s,0x61,65535)&32));expect(rd(s,0x61,65536)&32);
    // Counter latch survives advancing time and ignores relatch until consumed.
    wr(s,0x43,0xb0,70000);wr(s,0x42,0x34,70000);wr(s,0x42,0x12,70000);
    wr(s,0x43,0x80,70001);expect(rd(s,0x42,70002)==0x33);wr(s,0x43,0x80,70003);expect(rd(s,0x42,70500)==0x12);
    // Read-back can latch status and count; status is read first.
    wr(s,0x43,0xc8,70004);expect(rd(s,0x42,71000)==0x30);expect(rd(s,0x42,71000)==0x30);expect(rd(s,0x42,71000)==0x12);
    // Gate low pauses one-shot; gate high resumes remaining count.
    wr(s,0x61,0,70010);expect(pc_pit_count(s+256,90000)==0x1234-10);wr(s,0x61,1,90000);expect(pc_pit_count(s+256,90001)==0x1234-11);
    // Mode 2 pulse, gate restart, mode 6 alias and two byte reads.
    wr(s,0x43,0xb4,100000);wr(s,0x42,4,100000);wr(s,0x42,0,100000);
    expect(pc_pit_count(s+256,100002)==2);expect(!(rd(s,0x61,100003)&32));expect(rd(s,0x61,100004)&32);
    wr(s,0x61,0,100005);expect(rd(s,0x61,100100)&32);wr(s,0x61,1,100100);expect(pc_pit_count(s+256,100100)==4);
    wr(s,0x43,0xbc,100200);expect(load64(s+256+32)==2);
    // Odd mode-3 divisor: high for three clocks, low for two clocks.
    wr(s,0x43,0xb6,101000);wr(s,0x42,5,101000);wr(s,0x42,0,101000);
    expect(pc_pit_count(s+256,101000)==5);expect(pc_pit_count(s+256,101001)==4);expect(pc_pit_count(s+256,101002)==2);
    expect(pc_pit_out(s+256,101002));expect(!pc_pit_out(s+256,101003));expect(pc_pit_count(s+256,101003)==4);expect(pc_pit_count(s+256,101004)==2);expect(pc_pit_out(s+256,101005));
    // Mode 4 strobe lasts exactly one clock; MSB-only and LSB-only transfers.
    wr(s,0x43,0x98,102000);wr(s,0x42,3,102000);expect(pc_pit_out(s+256,102002));expect(!pc_pit_out(s+256,102003));expect(pc_pit_out(s+256,102004));
    wr(s,0x43,0xa0,103000);wr(s,0x42,2,103000);expect(load64(s+256)==512);expect(rd(s,0x42,103000)==2);
    expect(wr(s,0x43,0xb1,103000)==-1);expect(wr(s,0x43,0xb2,103000)==-1);expect(pc_pit_io(s,0x43,1,0,d,1,103000)==-1);
    syscall(11,d,8,0,0,0,0);syscall(11,s,512,0,0,0,0);return 0;
}
