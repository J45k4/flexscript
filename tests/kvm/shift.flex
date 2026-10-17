import "../../emulator/x86/cpu.flex";
fn expect(v) {if !v {syscall(1,2,"Double shift assertion failed\n",30,0,0,0);syscall(60,1,0,0,0,0,0);}return 0;}
fn main(argc,argv) {
    expect(argc==2 || argc==3);x86_jit_enabled=argc==3;x86_jit_min_fuel=0;x86_jit_threshold=1;
    let ram=alloc(1048576);let c=x86_create(ram,1048576);let run=alloc(4096);let row=alloc(64);let fd=syscall(2,load64(argv+8),0,0,0,0,0);expect(fd>=0);let cases=0;
    let bytes=syscall(0,fd,row,64,0,0,0);while bytes {
        expect(bytes==64);let width=load64(row);let right=load64(row+8)&1;let immediate=load64(row+8)&256;let memory=0;
        while memory<2 {
            x86_start(c,0x1000,32,0,0);store64(c+144,64);store64(c,load64(row+16));store64(c+16,load64(row+24));store64(c+8,load64(row+32));store64(c+136,0xad7);
            let p=ram+0x1000;let n=0;if width==2 {store8(p,0x66);n=1;}if width==8 {store8(p,0x48);n=1;}
            store8(p+n,0x0f);let op=0xa5;if right {op=0xad;}if immediate {op=op-1;}store8(p+n+1,op);n=n+2;
            if memory {store8(p+n,0x14);store8(p+n+1,0x25);n=n+2;let j=0;while j<4 {store8(p+n+j,0x2000>>(j*8));j=j+1;}n=n+4;store64(ram+0x2000,load64(row+16));}
            else {store8(p+n,0xd0);n=n+1;}
            if immediate {store8(p+n,1);n=n+1;}store8(p+n,0xf4);expect(x86_run(c,run,100)==5);
            let result=load64(c);let wanted=load64(row+40);if memory {result=load64(ram+0x2000)&x86_mask(width);wanted=wanted&x86_mask(width);}
            let count=load64(row+32)&31;if width==8 {count=load64(row+32)&63;}let mask=0x8d5;if count>1 {mask=0xc5;}else if count {mask=0x8c5;}
            if result!=wanted || (load64(c+136)&mask)!=(load64(row+48)&mask) {syscall(1,2,row,64,0,0,0);expect(0);}memory=memory+1;
        }cases=cases+1;bytes=syscall(0,fd,row,64,0,0,0);
    }
    expect(cases>2000);syscall(3,fd,0,0,0,0,0);x86_close(c);syscall(11,ram,1048576,0,0,0,0);syscall(11,run,4096,0,0,0,0);syscall(11,row,64,0,0,0,0);return 0;
}
