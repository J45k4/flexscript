import "../../lib/x86.flex";
fn expect(v) {if !v {syscall(1,2,"MXCSR assertion failed\n",23,0,0,0);syscall(60,1,0,0,0,0,0);}return 0;}
fn reset(c,ram,text) {expect(x86_start(c,0x1000,32,0,0));store64(c+144,64);store64(c+168,512);xf_hex(ram+0x1000,text);return 0;}
fn main(argc,argv) {
    expect(argc==2 || argc==3);x86_jit_enabled=argc==3;x86_jit_min_fuel=0;x86_jit_threshold=1;
    let ram=alloc(1048576);let c=x86_create(ram,1048576);let run=alloc(4096);let row=alloc(40);
    let fd=syscall(2,load64(argv+8),0,0,0,0,0);expect(fd>=0 && syscall(0,fd,row,8,0,0,0)==8);
    let mask=load64(row);expect(mask==xf_mxcsr_mask() && (load64(c+1048)>>32)==mask);
    let mode=0;while mode<4 {
        expect(syscall(0,fd,row,40,0,0,0)==40);
        reset(c,ram,"0fae142500200000f30f10042510200000f30f58042518200000f30f110425202000000fae1c2528200000f4");
        store64(ram+0x2000,load64(row));store64(ram+0x2010,1);store64(ram+0x2018,0);
        expect(x86_run(c,run,100)==5 && (load64(ram+0x2020)&0xffffffff)==load64(row+8) && (load64(ram+0x2028)&0xffffffff)==load64(row+16));
        reset(c,ram,"0fae142500200000f30f10042510200000f30f59042518200000f30f110425202000000fae1c2528200000f4");
        store64(ram+0x2010,0x00800000);store64(ram+0x2018,0x3f000000);
        expect(x86_run(c,run,100)==5 && (load64(ram+0x2020)&0xffffffff)==load64(row+24) && (load64(ram+0x2028)&0xffffffff)==load64(row+32));
        // Save and restore the same DAZ/FTZ mode, including the advertised mask.
        reset(c,ram,"0fae142500200000480fae0425003000000fae142508200000480fae0c25003000000fae1c2528200000f4");
        store64(ram+0x2008,0x1f80);
        expect(x86_run(c,run,100)==5 && (load64(ram+0x2028)&0xffffffff)==load64(row) && (load64(ram+0x3018)>>32)==mask);
        // A reserved bit must still fault without partially restoring FP state.
        reset(c,ram,"480fae0c2500300000f4");store64(ram+0x3018,0x10000);store64(c+1184,0x1122334455667788);
        expect(x86_run(c,run,100)==-1 && load64(c+392)==2 && (load64(c+1048)&0xffffffff)==0x1f80 && load64(c+1184)==0x1122334455667788);
        mode=mode+1;
    }
    expect(syscall(0,fd,row,1,0,0,0)==0);syscall(3,fd,0,0,0,0,0);x86_close(c);return 0;
}
