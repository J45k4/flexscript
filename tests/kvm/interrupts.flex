import "../../lib/x86.flex";
import "../../lib/pc-pit.flex";
import "../../lib/pc-pic.flex";
fn expect(v) {if !v {syscall(60,1,0,0,0,0,0);}return 0;}
fn digit(v) {if v>=97 {return v-87;}return v-48;}
fn code(p,text) {let i=0;while load8(text+i*2) {store8(p+i,digit(load8(text+i*2))*16+digit(load8(text+i*2+1)));i=i+1;}return i;}
fn setup(c,ram) {
    expect(x86_start(c,0x1000,32,0,0));store64(c+144,64);store64(c+152,0x80010001);store64(c+160,0x10000);store64(c+168,32);store64(c+176,1280);
    store64(ram+0x10000,0x11003);store64(ram+0x11000,0x12003);store64(ram+0x12000,0x83);
    store64(c+184,0x3000);store64(c+192,31);store64(c+376,16);store64(c+384,24);store64(c+32,0x9008);
    store64(ram+0x3010,0x00af9a000000ffff);store64(ram+0x3018,0x00cf92000000ffff);store64(c+320,0x4000);store64(c+328,4095);return 0;
}
fn gate(ram,vector,type) {store64(ram+0x4000+vector*16,0x0000800000102000|(type<<40));store64(ram+0x4008+vector*16,0);return 0;}
fn main() {
    let ram=alloc(2097152);let c=x86_create(ram,2097152);let run=alloc(4096);let pit=alloc(512);let pic=alloc(256);let data=alloc(8);let engine=0;
    while engine<2 {
        x86_jit_enabled=engine;x86_jit_min_fuel=0;x86_jit_threshold=1;
        setup(c,ram);gate(ram,32,14);code(ram+0x1000,"fb90e480f4");code(ram+0x2000,"488904251060000048ff04250060000048cf");store64(ram+0x6000,0);
        // STI inhibits maskable interrupts through the following instruction.
        expect(x86_run_slice(c,run,100,1)==10 && (load64(c+136)&512));expect(!x86_irq(c,32));
        expect(x86_run_slice(c,run,100,2)==10 && load64(c+312)==2);expect(x86_run(c,run,100)==2 && load64(c+280)==1);
        pc_pit_init(pit);pc_pic_init(pic);store8(data,0xfe);expect(pc_pic_io(pic,0x21,1,1,data,1));
        expect(!pc_pit_irq(pit,65535));expect(pc_pit_irq(pit,65536));expect(!pc_pit_irq(pit,65536));pc_pic_raise(pic,0);
        // A real PIT edge passes through masking/acknowledgment and the CPU IDT.
        expect(pc_pic_vector(pic)==8);store64(pic+24,32);expect(pc_pic_vector(pic)==32);
        expect(x86_irq(c,32));expect(!x86_irq(c,33));expect(pc_pic_take(pic)==32);store64(run+128,0xab);
        expect(x86_run(c,run,100)==5 && load64(ram+0x6000)==1 && load64(ram+0x6010)==0xab && load64(c+336)==1);
        expect(load64(c+32)==0x9008 && load64(c+128)==0x1005 && (load64(c+136)&512));
        // The five-qword frame preserves the unaligned interrupted stack.
        expect(load64(ram+0x8ff8)==24 && load64(ram+0x8ff0)==0x9008 && (load64(ram+0x8fe8)&512) && load64(ram+0x8fe0)==16 && load64(ram+0x8fd8)==0x1004);
        // Invalid RDMSR raises #GP(0); the handler skips it and returns with IF.
        setup(c,ram);gate(ram,13,14);store64(c+328,223);store64(c+136,514);store64(c+8,0x87);code(ram+0x1000,"0f32f4");
        code(ram+0x2000,"488b1c244883442408024883c40848cf");expect(x86_run(c,run,100)==5 && !load64(c+24) && load64(c+32)==0x9008 && (load64(c+136)&512));
        // INT3 is a trap: its no-error-code frame resumes after the breakpoint.
        setup(c,ram);gate(ram,3,15);store64(c+328,63);code(ram+0x1000,"ccf4");code(ram+0x2000,"488b1c2448cf");expect(x86_run(c,run,100)==5 && load64(c+24)==0x1001 && load64(c+32)==0x9008);
        // #NM is a fault: clear CR0.TS in the handler and retry FNINIT.
        setup(c,ram);gate(ram,7,14);store64(c+152,load64(c+152)|8);code(ram+0x1000,"dbe3f4");code(ram+0x2000,"0f20c04883e0f70f22c048cf");expect(x86_run(c,run,100)==5 && !(load64(c+152)&8) && xf_u16(c+1024)==0x37f);
        // Missing gate and unsupported IST fail visibly instead of dispatching.
        setup(c,ram);store64(c+136,514);gate(ram,32,14);store64(ram+0x4200,load64(ram+0x4200)|(1<<32));expect(x86_irq(c,32));expect(x86_run(c,run,100)==-1);
        engine=engine+1;
    }
    x86_close(c);syscall(11,ram,2097152,0,0,0,0);syscall(11,run,4096,0,0,0,0);syscall(11,pit,512,0,0,0,0);syscall(11,pic,256,0,0,0,0);syscall(11,data,8,0,0,0,0);return 0;
}
