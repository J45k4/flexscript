import "../../emulator/pc/ps2.flex";
import "../../emulator/pc/pic.flex";
fn expect(v) {if !v {syscall(1,2,"PS/2 assertion failed\n",21,0,0,0);syscall(60,1,0,0,0,0,0);}return 0;}
fn main() {
    let s=alloc(512);let pic=alloc(256);let data=alloc(16);pc_ps2_init(s);pc_pic_init(pic);
    expect(pc_ps2_status(s)==0x14 && !pc_ps2_irq(s));
    expect(pc_ps2_command(s,0xaa)==1 && pc_ps2_read(s)==0x55);
    expect(pc_ps2_command(s,0x20)==1 && pc_ps2_read(s)==0x34);
    expect(pc_ps2_command(s,0x60)==1 && pc_ps2_data(s,7)==1);
    expect(pc_ps2_command(s,0xa9)==1 && pc_ps2_read(s)==0);expect(pc_ps2_command(s,0xab)==1 && pc_ps2_read(s)==0);
    // Controller AUX-loopback is used to detect both the port and its IRQ.
    expect(pc_ps2_command(s,0xd3)==1 && pc_ps2_data(s,0x5a)==1 && (pc_ps2_status(s)&33)==33);
    expect(pc_ps2_irq(s)==12 && !pc_ps2_irq(s));store64(pic,0xfb);store64(pic+128,0xef);store64(pic+24,32);store64(pic+152,40);
    expect(pc_pic_raise(pic,12) && pc_pic_vector(pic)==44 && pc_pic_take(pic)==44);expect(pc_ps2_read(s)==0x5a && !pc_ps2_irq(s));
    // Keyboard identity/reset/query and host make/release events.
    expect(pc_ps2_data(s,0xff)==1 && pc_ps2_read(s)==0xfa && pc_ps2_read(s)==0xaa);
    expect(pc_ps2_data(s,0xf2)==1 && pc_ps2_read(s)==0xfa && pc_ps2_read(s)==0xab && pc_ps2_read(s)==0x83);
    expect(pc_ps2_data(s,0xf0)==1 && pc_ps2_read(s)==0xfa && pc_ps2_data(s,0)==1 && pc_ps2_read(s)==0xfa && pc_ps2_read(s)==2);
    expect(pc_ps2_key(s,0x1c,0,1) && pc_ps2_irq(s)==1 && pc_ps2_read(s)==0x1c);
    expect(pc_ps2_key(s,0x75,1,0) && pc_ps2_read(s)==0xe0 && pc_ps2_read(s)==0xf0 && pc_ps2_read(s)==0x75);
    expect(pc_ps2_data(s,0xed)==1 && pc_ps2_read(s)==0xfa && pc_ps2_data(s,5)==1 && pc_ps2_read(s)==0xfa && load64(s+80)==5);
    expect(pc_ps2_data(s,0xf5)==1 && pc_ps2_read(s)==0xfa && !pc_ps2_key(s,0x1c,0,1));
    expect(pc_ps2_data(s,0xf4)==1 && pc_ps2_read(s)==0xfa);
    expect(pc_ps2_command(s,0xad)==1 && !pc_ps2_key(s,0x1c,0,1));expect(pc_ps2_command(s,0xae)==1);
    // Mouse responds on AUX, and emits signed relative motion + buttons.
    expect(pc_ps2_command(s,0xd4)==1 && pc_ps2_data(s,0xff)==1);expect(pc_ps2_read(s)==0xfa && pc_ps2_read(s)==0xaa && pc_ps2_read(s)==0);
    expect(pc_ps2_command(s,0xd4)==1 && pc_ps2_data(s,0xf4)==1 && pc_ps2_read(s)==0xfa);
    expect(pc_ps2_motion(s,-10,20,1) && (pc_ps2_status(s)&32) && pc_ps2_irq(s)==12);
    expect(pc_ps2_read(s)==0x19 && pc_ps2_read(s)==246 && pc_ps2_read(s)==20);
    expect(pc_ps2_motion(s,300,-300,0) && pc_ps2_read(s)==0xe8 && pc_ps2_read(s)==255 && pc_ps2_read(s)==1);
    // Scaling and remote mode preserve the standard PS/2 packet protocol.
    pc_ps2_command(s,0xd4);pc_ps2_data(s,0xe7);expect(pc_ps2_read(s)==0xfa);
    expect(pc_ps2_motion(s,4,-2,0) && pc_ps2_read(s)==0x28 && pc_ps2_read(s)==6 && pc_ps2_read(s)==255);
    pc_ps2_command(s,0xd4);pc_ps2_data(s,0xf0);expect(pc_ps2_read(s)==0xfa);
    expect(pc_ps2_motion(s,4,-2,3) && pc_ps2_motion(s,2,1,3) && !(pc_ps2_status(s)&1));
    pc_ps2_command(s,0xd4);pc_ps2_data(s,0xeb);expect(pc_ps2_read(s)==0xfa && pc_ps2_read(s)==0x2b && pc_ps2_read(s)==6 && pc_ps2_read(s)==255);
    pc_ps2_command(s,0xd4);pc_ps2_data(s,0xee);expect(pc_ps2_read(s)==0xfa);
    pc_ps2_command(s,0xd4);pc_ps2_data(s,0xf2);expect(pc_ps2_read(s)==0xf2 && !pc_ps2_motion(s,1,1,0));
    pc_ps2_command(s,0xd4);pc_ps2_data(s,0xec);expect(pc_ps2_read(s)==0xfa);
    // Controller interrupt enables are independent of the data buffers.
    expect(pc_ps2_command(s,0x60)==1 && pc_ps2_data(s,4)==1);expect(pc_ps2_key(s,0x1c,0,1) && !pc_ps2_irq(s));
    expect(pc_ps2_command(s,0x60)==1 && pc_ps2_data(s,7)==1 && pc_ps2_irq(s)==1 && pc_ps2_read(s)==0x1c);
    // FIFO wrap and overflow preserve all previously queued bytes.
    let i=0;while i<128 {expect(pc_ps2_put(s,i,0)==1 && pc_ps2_read(s)==i);i=i+1;}
    i=0;while i<64 {expect(pc_ps2_put(s,i,0)==1);i=i+1;}expect(pc_ps2_put(s,99,0)==-1 && !pc_ps2_key(s,0x75,1,0));
    i=0;while i<64 {expect(pc_ps2_read(s)==i);i=i+1;}
    // Unknown modes fail visibly rather than silently enabling translation/reset.
    expect(pc_ps2_command(s,0x60)==1 && pc_ps2_data(s,0x47)==-1);
    expect(pc_ps2_data(s,0xf0)==1 && pc_ps2_read(s)==0xfa && pc_ps2_data(s,3)==1 && pc_ps2_read(s)==0xfe);
    expect(pc_ps2_command(s,0xd1)==1 && pc_ps2_data(s,0)==-1);
    expect(!pc_ps2_io(s,0x60,2,0,data,1));
    store8(data,0xaa);expect(pc_ps2_io(s,0x64,1,1,data,1)==1 && pc_ps2_io(s,0x60,1,0,data,1)==1 && load8(data)==0x55);
    syscall(11,data,16,0,0,0,0);syscall(11,pic,256,0,0,0,0);syscall(11,s,512,0,0,0,0);return 0;
}
