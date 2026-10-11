import "../../lib/x86.flex";
fn expect(v) {if !v {syscall(1,2,"vector word assertion failed\n",29,0,0,0);syscall(60,1,0,0,0,0,0);}return 0;}
fn reset(c,ram,text) {expect(x86_start(c,0x1000,32,0,0));store64(c+144,64);store64(c+168,512);store64(c+136,0x8d7);xf_hex(ram+0x1000,text);return 0;}
fn main(argc,argv) {
    expect(argc==2 || argc==3);x86_jit_enabled=argc==3;x86_jit_min_fuel=0;x86_jit_threshold=1;
    let ram=alloc(1048576);let c=x86_create(ram,1048576);let run=alloc(4096);let row=alloc(64);let fd=syscall(2,load64(argv+8),0,0,0,0,0);expect(fd>=0);
    let i=0;while i<256 {
        expect(syscall(0,fd,row,64,0,0,0)==64);let wide=0;while wide<2 {
            reset(c,ram,"66450fc5d700f4");store8(ram+0x1001,0x45+wide*8);store8(ram+0x1005,load64(row));
            store64(c+1184+15*16,load64(row+8));store64(c+1192+15*16,load64(row+16));store64(c+80,-1);
            expect(x86_run(c,run,100)==5 && load64(c+80)==load64(row+32) && load64(c+136)==0x8d7);
            reset(c,ram,"66450fc4fa00f4");store8(ram+0x1001,0x45+wide*8);store8(ram+0x1005,load64(row));
            store64(c+1184+15*16,load64(row+8));store64(c+1192+15*16,load64(row+16));store64(c+80,load64(row+24));
            expect(x86_run(c,run,100)==5 && load64(c+1184+15*16)==load64(row+40) && load64(c+1192+15*16)==load64(row+48) && load64(c+136)==0x8d7);
            wide=wide+1;
        }
        reset(c,ram,"66440fc43c250020000000f4");store8(ram+0x100a,load64(row));store64(ram+0x2000,load64(row+24));
        store64(c+1184+15*16,load64(row+8));store64(c+1192+15*16,load64(row+16));
        expect(x86_run(c,run,100)==5 && load64(c+1184+15*16)==load64(row+40) && load64(c+1192+15*16)==load64(row+48));i=i+1;
    }
    reset(c,ram,"66440fc43c25ffff0f0000f4");store64(c+1184+15*16,0x1122334455667788);
    expect(x86_run(c,run,100)==-1 && load64(c+1184+15*16)==0x1122334455667788);
    reset(c,ram,"66440fc53c250020000000f4");store64(c+120,-1);
    expect(x86_run(c,run,100)==-1 && load64(c+392)==262 && load64(c+120)==-1);
    expect(syscall(0,fd,row,1,0,0,0)==0);syscall(3,fd,0,0,0,0,0);x86_close(c);return 0;
}
