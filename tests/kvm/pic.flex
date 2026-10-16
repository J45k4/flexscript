import "../../emulator/pc/pic.flex";
fn expect(v) {if !v {syscall(60,1,0,0,0,0,0);}return 0;}
fn wr(s,p,v) {let d=alloc(8);store8(d,v);let r=pc_pic_io(s,p,1,1,d,1);syscall(11,d,8,0,0,0,0);return r;}
fn rd(s,p) {let d=alloc(8);expect(pc_pic_io(s,p,1,0,d,1)==1);let v=load8(d);syscall(11,d,8,0,0,0,0);return v;}
fn main() {
    let s=alloc(256);pc_pic_init(s);expect(rd(s,0x21)==255 && rd(s,0xa1)==255);
    expect(wr(s,0x20,0x11)==1);wr(s,0x21,0x30);wr(s,0x21,4);wr(s,0x21,1);
    wr(s,0xa0,0x11);wr(s,0xa1,0x38);wr(s,0xa1,2);wr(s,0xa1,1);
    wr(s,0x21,0xf8);wr(s,0xa1,0xfd);
    // Masked requests remain latched; nested IRQ0 outranks IRQ1 in service.
    pc_pic_raise(s,1);pc_pic_raise(s,3);expect(pc_pic_vector(s)==0x31);expect(pc_pic_take(s)==0x31);
    wr(s,0x20,0x0b);expect(rd(s,0x20)==2);expect(pc_pic_vector(s)==-1);
    pc_pic_raise(s,0);expect(pc_pic_take(s)==0x30);expect(rd(s,0x20)==3);wr(s,0x20,0x20);expect(rd(s,0x20)==2);
    wr(s,0x20,0x61);expect(rd(s,0x20)==0);wr(s,0x20,0x0a);expect(rd(s,0x20)==8);wr(s,0x21,0xf0);expect(pc_pic_take(s)==0x33);wr(s,0x20,0x63);
    // Cascaded IRQ9 acknowledges both controllers and requires both EOIs.
    pc_pic_raise(s,9);expect(pc_pic_vector(s)==0x39);expect(pc_pic_take(s)==0x39);
    wr(s,0xa0,0x0b);wr(s,0x20,0x0b);expect(rd(s,0xa0)==2 && rd(s,0x20)==4);
    pc_pic_raise(s,9);expect(pc_pic_vector(s)==-1);wr(s,0xa0,0x61);expect(pc_pic_vector(s)==-1);wr(s,0x20,0x62);expect(pc_pic_take(s)==0x39);
    wr(s,0xa0,0x61);wr(s,0x20,0x62);
    // Masking cascade blocks delivery without losing the slave request.
    wr(s,0x21,0xff);pc_pic_raise(s,9);expect(pc_pic_vector(s)==-1);wr(s,0x21,0xfb);expect(pc_pic_take(s)==0x39);wr(s,0xa0,0x61);wr(s,0x20,0x62);
    // Poll acknowledges exactly once; automatic EOI keeps ISR clear.
    wr(s,0x20,0x11);wr(s,0x21,0x20);wr(s,0x21,4);wr(s,0x21,3);wr(s,0x21,0xfe);
    pc_pic_raise(s,0);wr(s,0x20,0x0c);expect(rd(s,0x20)==0x80);expect(pc_pic_vector(s)==-1);wr(s,0x20,0x0b);expect(!rd(s,0x20));
    expect(wr(s,0x20,0x19)==-1);expect(wr(s,0x20,0xa0)==-1);expect(wr(s,0x20,0x68)==-1);
    let d=alloc(8);expect(!pc_pic_io(s,0x20,2,0,d,1));expect(!pc_pic_raise(s,16));expect(!pc_pic_raise(s,2));syscall(11,d,8,0,0,0,0);syscall(11,s,256,0,0,0,0);return 0;
}
