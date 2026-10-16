import "../../emulator/backends/software.flex";
fn expect(value) {if !value {syscall(1,2,"x86 wide arithmetic assertion failed\n",37,0,0,0);syscall(60,1,0,0,0,0,0);}return 0;}
fn main(argc,argv) {
    expect(argc==2 || argc==3);if argc==3 {x86_jit_enabled=1;x86_jit_min_fuel=0;x86_jit_threshold=1;}else {x86_jit_enabled=0;}let fd=syscall(2,load64(argv+8),0,0,0,0,0);expect(fd>=0);
    let v=softvm_create(1048576);expect(v);let c=load64(v+64);let ram=load64(v+24);let run=load64(v+40);let record=alloc(64);let cases=0;
    let active=1;while active {
        let n=syscall(0,fd,record,64,0,0,0);if !n {active=0;}else {expect(n==64);
        expect(x86_start(c,0x1000,32,0,0));store64(c+144,64);store64(c,load64(record+16));store64(c+16,load64(record+24));store64(c+8,load64(record+32));
        store8(ram+0x1000,0x48);store8(ram+0x1001,0xf7);store8(ram+0x1002,0xc1+load64(record)*8);store8(ram+0x1003,0xf4);
        expect(x86_run(c,run,100)==5);
        expect(load64(c)==load64(record+40) && load64(c+16)==load64(record+48));
        if load64(record)<6 {expect((load64(c+136)&0x801)==(load64(record+56)&0x801));}cases=cases+1;}
    }
    expect(cases==1121);softvm_close(v);syscall(3,fd,0,0,0,0,0);syscall(11,record,64,0,0,0,0);return 0;
}
