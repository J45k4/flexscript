import "../../lib/x86.flex";
fn expect(v) {if !v {syscall(1,2,"segment verify assertion failed\n",32,0,0,0);syscall(60,1,0,0,0,0,0);}return 0;}
fn main(argc,argv) {
    let ram=alloc(131072);let c=x86_create(ram,131072);let run=alloc(4096);let engine=0;
    expect(argc==2);let fd=syscall(2,load64(argv+8),0,0,0,0,0);expect(fd>=0);let oracle=alloc(4096);let size=syscall(0,fd,oracle,4096,0,0,0);syscall(3,fd,0,0,0,0,0);expect(size>=48*32 && !(size&31));
    while engine<2 {
        x86_jit_enabled=engine;x86_jit_min_fuel=0;x86_jit_threshold=1;
        let at=0;while at<size {let g=4;while g<=5 {
            expect(x86_start(c,0x1000,32,load64(oracle+at+8),0));store64(c+376,3);store64(c+184,0x3000);store64(c+192,23);store64(c+136,0x8d7);store64(ram+0x3010,load64(oracle+at));
            store8(ram+0x1000,15);store8(ram+0x1001,0);store8(ram+0x1002,0xc0+g*8);store8(ram+0x1003,0xf4);
            expect(x86_run_slice(c,run,100,1)==10 && ((load64(c+136)&64)!=0)==load64(oracle+at+16+(g-4)*8));g=g+1;
        }at=at+32;}
        let group=4;while group<=5 {let type=0;while type<16 {let dpl=0;while dpl<4 {let cpl=0;while cpl<4 {let rpl=0;while rpl<4 {
            expect(x86_start(c,0x1000,32,16+rpl,0));store64(c+376,cpl);store64(c+184,0x3000);store64(c+192,23);store64(c+136,0x8d7);
            store64(ram+0x3010,0x00cf10000000ffff|(type<<40)|(dpl<<45));
            store8(ram+0x1000,0x0f);store8(ram+0x1001,0);store8(ram+0x1002,0xc0+group*8);store8(ram+0x1003,0xf4);
            let accessible=dpl>=cpl && dpl>=rpl;if group==4 && (type&12)==12 {accessible=1;}
            let valid=accessible && (!(type&8) || (type&2));if group==5 {valid=accessible && !(type&8) && (type&2);}
            expect(x86_run_slice(c,run,100,1)==10 && load64(c+136)==((0x8d7&~64)|(valid!=0)*64) && load64(c)==16+rpl);
            rpl=rpl+1;}cpl=cpl+1;}dpl=dpl+1;}type=type+1;}group=group+1;}
        // The kernel's RIP-relative memory VERW form, null, LDT and limit cases.
        let selector=0;while selector<40 {
            expect(x86_start(c,0x1000,32,0,0));store64(c+144,64);store64(c+184,0x3000);store64(c+192,23);store64(ram+0x3010,0x00cf92000000ffff);
            store64(ram+0x1000,0x000009f92d000f);store8(ram+0x1007,0xf4);store8(ram+0x1a00,selector);store8(ram+0x1a01,0);
            expect(x86_run(c,run,100)==5 && ((load64(c+136)&64)!=0)==(selector==16));selector=selector+1;
        }
        engine=engine+1;
    }x86_close(c);syscall(1,1,"segment verify tests passed\n",28,0,0,0);return 0;
}
