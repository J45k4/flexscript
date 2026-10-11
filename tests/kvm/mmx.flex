import "../../lib/x86.flex";
fn expect(v) {if !v {syscall(1,2,"MMX assertion failed\n",21,0,0,0);syscall(60,1,0,0,0,0,0);}return 0;}
fn reset(c) {expect(x86_start(c,0x1000,32,0,0));store64(c+144,64);return 0;}
fn main(argc,argv) {
    expect(argc==2 || argc==3);x86_jit_enabled=argc==3;x86_jit_min_fuel=0;x86_jit_threshold=1;
    let ram=alloc(1048576);let c=x86_create(ram,1048576);let run=alloc(4096);let row=alloc(64);let fd=syscall(2,load64(argv+8),0,0,0,0,0);expect(fd>=0);
    let codes=alloc(128);store64(codes,"0fefdd");store64(codes+8,"0ffcdd");store64(codes+16,"0feddd");store64(codes+24,"0fd9dd");store64(codes+32,"0fd5dd");store64(codes+40,"0fe5dd");store64(codes+48,"0ff5dd");store64(codes+56,"0f63dd");store64(codes+64,"0f68dd");store64(codes+72,"0f76dd");store64(codes+80,"0f65dd");store64(codes+88,"0fd1dd");store64(codes+96,"0f71e307");store64(codes+104,"0f73f33f");store64(codes+112,"0fdfdd");store64(codes+120,"0fd4dd");
    let cases=0;while cases<1024 {
        expect(syscall(0,fd,row,64,0,0,0)==64);reset(c);store64(ram+0x2000,load64(row+8));store64(ram+0x2008,load64(row+16));
        let n=xf_hex(ram+0x1000,"0f6f1c25002000000f6f2c2508200000");n=n+xf_hex(ram+0x1000+n,load64(codes+load64(row)*8));store8(ram+0x1000+n,0xf4);
        expect(x86_run(c,run,100)==5 && load64(c+1056+3*16)==load64(row+24) && xf_u16(c+1024)==load64(row+32) && xf_u16(c+1026)==load64(row+40) && load8(c+1028)==load64(row+48) && xf_u16(c+1064+3*16)==load64(row+56));cases=cases+1;
    }
    while cases<1152 {
        expect(syscall(0,fd,row,64,0,0,0)==64);reset(c);store64(ram+0x2000,load64(row+8));store64(c,load64(row+24)&0xffffffff);store64(c+16,(load64(row+24)>>32)&0xffffffff);store64(c+24,load64(row+16)&0xffffffff);store64(c+8,(load64(row+16)>>32)&0xffffffff);store64(c+136,0x8d7);
        xf_hex(ram+0x1000,"f00fc70c2500200000f4");expect(x86_run(c,run,100)==5 && load64(ram+0x2000)==load64(row+32) && (load64(c)|(load64(c+16)<<32))==load64(row+40) && ((load64(c+136)>>6)&1)==load64(row+48) && (load64(c+136)&~64)==(0x8d7&~64));cases=cases+1;
    }
    reset(c);store64(c,1);x86_cpuid(c);expect((load64(c+16)&0x7808101)==0x7808101 && load64(c+8)==0x80000000);store64(c,0x40000000);x86_cpuid(c);expect(load64(c+24)==0x78656c46 && load64(c+8)==0x74666f53 && load64(c+16)==0x74726956);
    // A failed locked CMPXCHG8B still requires write permission. No partial store.
    reset(c);store64(c,1);store64(c+16,2);xf_hex(ram+0x1000,"f00fc70c25fcff0f00f4");expect(x86_run(c,run,100)==-1 && load64(c)==1 && load64(c+16)==2);
    // MOVD zeroes the upper significand; REX.W transfers a full qword.
    reset(c);store64(c+80,0xfedcba9876543210);xf_hex(ram+0x1000,"410f6eda490f7edb0f77f4");expect(x86_run(c,run,100)==5 && load64(c+88)==0x76543210 && !load8(c+1028));
    reset(c);store64(c+80,0xfedcba9876543210);xf_hex(ram+0x1000,"490f6eda490f7edbf4");expect(x86_run(c,run,100)==5 && load64(c+88)==0xfedcba9876543210 && load8(c+1028)==255);
    reset(c);store64(ram+1048568,99);xf_hex(ram+0x1000,"0f6f1c25f8ff0f000f7f1c2500200000f4");expect(x86_run(c,run,100)==5 && load64(ram+0x2000)==99);
    reset(c);xf_hex(ram+0x1000,"0f6f1c25fcff0f00f4");expect(x86_run(c,run,100)==-1 && !load8(c+1028));
    reset(c);store64(c+152,5);xf_hex(ram+0x1000,"0f77f4");expect(x86_run(c,run,100)==-1 && load64(c+392)==262);
    reset(c);store64(c+152,9);xf_hex(ram+0x1000,"0f77f4");expect(x86_run(c,run,100)==-1 && load64(c+392)==263);
    reset(c);xf_put16(c+1024,0x37e);xf_put16(c+1026,1);xf_hex(ram+0x1000,"0f77f4");expect(x86_run(c,run,100)==-1 && load64(c+392)==272);
    // MMX aliases physical x87 registers, including a nonzero x87 TOP.
    reset(c);xf_hex(ram+0x1000,"d9e8d9e80fefd20f77d9e8f4");expect(x86_run(c,run,100)==5 && load8(c+1028)==128 && ((xf_u16(c+1026)>>11)&7)==7);
    syscall(3,fd,0,0,0,0,0);x86_close(c);syscall(1,1,"MMX tests passed\n",17,0,0,0);return 0;
}
