import "../../lib/softvm.flex";
fn expect(condition) {if !condition {syscall(1,2,"x86 emulator assertion failed\n",30,0,0,0);syscall(60,1,0,0,0,0,0);}return 0;}
fn digit(c) {if c>=97 {return c-87;}return c-48;}
fn reset(c,ram,text,n) {x86_start(c,0x1000,32,0,0);let i=0;while i<n {store8(ram+0x1000+i,digit(load8(text+i*2))*16+digit(load8(text+i*2+1)));i=i+1;}return 0;}
fn main(argc,argv) {
    expect(argc==2 || argc==3);if argc==3 {x86_jit_enabled=1;x86_jit_min_fuel=0;x86_jit_threshold=1;}else {x86_jit_enabled=0;}let fd=syscall(2,load64(argv+8),0,0,0,0,0);expect(fd>=0);
    let v=softvm_create(1048576);expect(v!=0);let c=load64(v+64);let ram=load64(v+24);let run=load64(v+40);let record=alloc(48);let cases=0;
    while cases<18496 {
        let bytes=0;while bytes<48 {let n=syscall(0,fd,record+bytes,48-bytes,0,0,0);expect(n>0);bytes=bytes+n;}
        let width=load64(record);let op=load64(record+8)&255;x86_start(c,0x1000,32,0,0);store64(c+144,64);store64(c+136,2|((load64(record+8)>>8)&1));
        store64(c,load64(record+16));store64(c+8,load64(record+24));let p=ram+0x1000;let offset=0;
        if width==2 {store8(p,0x66);offset=1;}if width==8 {store8(p,0x48);offset=1;}
        let opcode=op*8;if width!=1 {opcode=opcode+1;}store8(p+offset,opcode);store8(p+offset+1,0xc8);store8(p+offset+2,0xf4);
        expect(x86_run(c,run,100)==5);
        let mask=0x8d5;if op==1 || op==4 || op==6 {mask=mask&~16;}
        if load64(c)!=load64(record+32) || (load64(c+136)&mask)!=(load64(record+40)&mask) {
            // Return case index through a binary diagnostic for reproducibility.
            syscall(1,2,record,48,0,0,0);expect(0);
        }if argc==3 && width>=4 {expect(load64(c+1008)>0);}cases=cases+1;
    }
    expect(cases==18496 && syscall(0,fd,record,48,0,0,0)==0);syscall(3,fd,0,0,0,0,0);syscall(11,record,48,0,0,0,0);
    // Decode, flags, addressing, boundaries and invalid operations.
    reset(c,ram,"0f0b",2);expect(x86_run(c,run,100)==-1 && load64(c+200)==0x1000);
    reset(c,ram,"ebfe",2);expect(x86_run(c,run,10)==-1 && x86_error==-110 && load64(c+312)==10);
    reset(c,ram,"666666666666666666666666666666f4",16);expect(x86_run(c,run,100)==-1);
    reset(c,ram,"488b0501000000f4",8);store64(c+144,64);store64(ram+0x1008,0x1122334455667788);expect(x86_run(c,run,100)==5 && load64(c)==0x1122334455667788);
    reset(c,ram,"488b448b10f4",6);store64(c+144,64);store64(c+24,0x2000);store64(c+8,3);store64(ram+0x201c,0x8877665544332211);expect(x86_run(c,run,100)==5 && load64(c)==0x8877665544332211);
    reset(c,ram,"b41240b434f4",6);store64(c+144,64);expect(x86_run(c,run,100)==5 && load64(c)==0x1200 && (load64(c+32)&255)==0x34);
    reset(c,ram,"48d1e8f4",4);store64(c+144,64);store64(c,0x8000000000000001);expect(x86_run(c,run,100)==5 && load64(c)==0x4000000000000000 && (load64(c+136)&0x801)==0x801);
    reset(c,ram,"48f7f9f4",4);store64(c+144,64);store64(c+8,0);expect(x86_run(c,run,100)==-1);
    reset(c,ram,"48f7f9f4",4);store64(c+144,64);store64(c,0x8000000000000000);store64(c+16,-1);store64(c+8,-1);expect(x86_run(c,run,100)==-1);
    reset(c,ram,"f4",1);expect(x86_read(c,1048575,2)==0 && load64(c+288));
    reset(c,ram,"f4",1);store8(ram+1048575,0xaa);expect(!x86_write(c,1048575,2,0xffff) && load8(ram+1048575)==0xaa);
    reset(c,ram,"0f1808f4",4);store64(c,-1);expect(x86_run(c,run,100)==5);
    reset(c,ram,"86e0f4",3);store64(c,0x1122334455661234);expect(x86_run(c,run,100)==5 && load64(c)==0x1122334455663412);
    reset(c,ram,"90f4",2);store64(c+144,64);store64(c,-1);expect(x86_run(c,run,100)==5 && load64(c)==-1);
    reset(c,ram,"4990f4",3);store64(c+144,64);store64(c,7);store64(c+64,9);expect(x86_run(c,run,100)==5 && load64(c)==9 && load64(c+64)==7);
    reset(c,ram,"480fc8f4",4);store64(c+144,64);store64(c,0x1122334455667788);expect(x86_run(c,run,100)==5 && load64(c)==0x8877665544332211);
    reset(c,ram,"0fc8f4",3);store64(c+144,64);store64(c,0x1122334455667788);expect(x86_run(c,run,100)==5 && load64(c)==0x88776655);
    // Single-vCPU LOCK CMPXCHG success/failure and XADD aliasing.
    reset(c,ram,"f0480fb113f4",6);store64(c+144,64);store64(c,7);store64(c+16,9);store64(c+24,0x2000);store64(ram+0x2000,7);
    expect(x86_run(c,run,100)==5 && load64(ram+0x2000)==9 && (load64(c+136)&64));
    reset(c,ram,"f0480fb113f4",6);store64(c+144,64);store64(c,8);store64(c+16,9);store64(c+24,0x2000);store64(ram+0x2000,7);
    expect(x86_run(c,run,100)==5 && load64(ram+0x2000)==7 && load64(c)==7 && !(load64(c+136)&64));
    reset(c,ram,"f0480fc100f4",6);store64(c+144,64);store64(c,0x2000);store64(ram+0x2000,5);
    expect(x86_run(c,run,100)==5 && load64(ram+0x2000)==0x2005 && load64(c)==5);
    reset(c,ram,"480fc1c0f4",5);store64(c+144,64);store64(c,7);expect(x86_run(c,run,100)==5 && load64(c)==14);
    reset(c,ram,"0fb1d1f4",4);store64(c+144,64);store64(c+8,0x1122334455667788);store64(c+16,1);expect(x86_run(c,run,100)==5 && load64(c)==0x55667788 && load64(c+8)==0x1122334455667788);
    reset(c,ram,"f090",2);expect(x86_run(c,run,100)==-1);
    reset(c,ram,"f0480fb1d0",5);store64(c+144,64);expect(x86_run(c,run,100)==-1);
    reset(c,ram,"8cd08cc9f4",5);store64(c+144,64);store64(c,-1);store64(c+8,-1);store64(c+384,24);store64(c+376,16);expect(x86_run(c,run,100)==5 && load64(c)==24 && load64(c+8)==16);
    reset(c,ram,"0f01000f014810f4",8);store64(c+144,64);store64(c,0x2000);store64(c+184,0x12345678);store64(c+192,31);store64(c+320,0x3456789a);store64(c+328,255);expect(x86_run(c,run,100)==5 && load8(ram+0x2000)==31 && load64(ram+0x2002)==0x12345678 && load8(ram+0x2010)==255 && load64(ram+0x2012)==0x3456789a);
    reset(c,ram,"b8200000000f00d80f00c9f4",12);store64(c+144,64);store64(c+184,0x18000);store64(c+192,47);store64(ram+0x18020,0x0000890030000067);store64(ram+0x18028,0);expect(x86_run(c,run,100)==5 && load64(c+8)==32 && load64(c+704)==32 && load64(c+712)==0x3000 && load64(c+720)==103 && ((load64(ram+0x18020)>>40)&15)==11);
    reset(c,ram,"b9810000c031c0ba100023000f3031d20f32f4",19);store64(c+144,64);expect(x86_run(c,run,100)==5 && !load64(c) && load64(c+16)==0x230010 && load64(c+736)==0x0023001000000000);
    reset(c,ram,"0f21f8f4",4);store64(c+144,64);expect(x86_run(c,run,100)==5 && load64(c)==0x400);
    reset(c,ram,"b8010000000f23f8f4",9);store64(c+144,64);expect(x86_run(c,run,100)==-1);
    // GS base MSR, segmented loads, LEA without segment base, SWAPGS and fences.
    reset(c,ram,"b9010100c0b80020000031d20f3065488b04251000000065488d1c25100000000f01f865488b0c25100000000faee80faef00faef8f4",54);store64(c+144,64);store64(c+480,0x3000);
    store64(ram+0x2010,0x1122334455667788);store64(ram+0x3010,0x8877665544332211);
    expect(x86_run(c,run,100)==5 && load64(c)==0x1122334455667788 && load64(c+24)==16 && load64(c+8)==0x8877665544332211);
    expect(load64(c+472)==0x3000 && load64(c+480)==0x2000);
    // Rotates preserve status flags other than CF/OF; full-width multiply/divide.
    reset(c,ram,"48c1c21ff4",5);store64(c+144,64);store64(c+16,0xa375452d4941bd07);store64(c+136,0xd6);
    expect(x86_run(c,run,100)==5 && load64(c+16)==0xa4a0de83d1baa296 && (load64(c+136)&0xd4)==0xd4);
    reset(c,ram,"c0c801f4",4);store64(c,0x81);expect(x86_run(c,run,100)==5 && load64(c)==0xc0 && (load64(c+136)&0x801)==1);
    reset(c,ram,"48f7e1f4",4);store64(c+144,64);store64(c,-1);store64(c+8,-1);
    expect(x86_run(c,run,100)==5 && load64(c)==1 && load64(c+16)==-2 && (load64(c+136)&0x801)==0x801);
    reset(c,ram,"48f7f1f4",4);store64(c+144,64);store64(c,0);store64(c+16,1);store64(c+8,3);
    expect(x86_run(c,run,100)==5 && load64(c)==0x5555555555555555 && load64(c+16)==1);
    reset(c,ram,"48f7f9f4",4);store64(c+144,64);store64(c,-100);store64(c+16,-1);store64(c+8,7);
    expect(x86_run(c,run,100)==5 && load64(c)==-14 && load64(c+16)==-2);
    reset(c,ram,"f3a4f4",3);store64(c+8,2000);store64(c+48,0x5000);store64(c+56,0x4000);store8(ram+0x5000,0xaa);
    expect(x86_run(c,run,100)==-1 && x86_error==-110 && load64(c+312)==100 && load64(c+8)==1900 && load64(c+48)==0x5064 && load64(c+56)==0x4064 && load8(ram+0x4000)==0xaa);
    // Four-level paging, non-identity mapping, cross-page access, WP and absence.
    reset(c,ram,"f4",1);store64(c+152,0x80010001);store64(c+160,0x10000);store64(c+168,32);store64(c+176,256);
    store64(ram+0x10000,0x11003);store64(ram+0x11000,0x12003);store64(ram+0x12000,0x13003);store64(ram+0x13000,0x20003);store64(ram+0x13008,0x30003);
    store8(ram+0x20fff,0x12);store8(ram+0x30000,0x34);expect(x86_read(c,0xfff,2)==0x3412);
    expect(x86_write(c,0xfff,2,0x5678) && load8(ram+0x20fff)==0x78 && load8(ram+0x30000)==0x56);
    store64(ram+0x13008,0x30001);expect(!x86_write(c,0xfff,2,0xffff) && load8(ram+0x20fff)==0x78);
    store64(c+288,0);store64(ram+0x13008,0);expect(x86_read(c,0x1000,1)==0 && load64(c+288));
    store64(c+288,0);expect(x86_read(c,0x0000800000000000,1)==0 && load64(c+288));
    // Demand-map an absent page in a guest #PF handler, then IRETQ and retry.
    reset(c,ram,"48c704250040000078563412f4",13);store64(c+144,64);
    store64(c+152,0x80010001);store64(c+160,0x10000);store64(c+168,32);store64(c+176,1280);
    store64(c+184,0x18000);store64(c+192,31);store64(c+376,16);store64(c+384,24);
    store64(ram+0x18010,0x00af9a000000ffff);store64(ram+0x18018,0x00cf92000000ffff);
    let j=0;while j<512 {store64(ram+0x13000+j*8,0);j=j+1;}
    store64(ram+0x10000,0x11003);store64(ram+0x11000,0x12003);store64(ram+0x12000,0x13003);
    j=0;while j<32 {if j!=4 {store64(ram+0x13000+j*8,j*4096+3);}j=j+1;}
    store64(c+320,0x19000);store64(c+328,239);store64(ram+0x190e0,0x00008f0000102000);store64(ram+0x190e8,0);
    // Handler: capture CR2/error, install PTE, drop error code, IRETQ.
    let handler="0f20d34c8b042448c7042520300100030003004883c40848cf";
    j=0;while j<25 {store8(ram+0x2000+j,digit(load8(handler+j*2))*16+digit(load8(handler+j*2+1)));j=j+1;}
    expect(x86_run(c,run,100)==5 && load64(ram+0x30000)==0x12345678);
    expect(load64(c+24)==0x4000 && load64(c+64)==2 && load64(c+32)==0x8000 && load64(c+368)==0x4000);
    // A page fault halfway through batched REP preserves completed iterations.
    store64(ram+0x13020,0);store8(ram+0x1000,0xf3);store8(ram+0x1001,0xaa);store8(ram+0x1002,0xf4);
    store64(c+128,0x1000);store64(c+312,0);store64(c,0x7f);store64(c+8,4);store64(c+56,0x3ffe);
    expect(x86_run(c,run,100)==5 && !load64(c+8) && load64(c+56)==0x4002);
    expect(load8(ram+0x3ffe)==0x7f && load8(ram+0x3fff)==0x7f && load8(ram+0x30000)==0x7f && load8(ram+0x30001)==0x7f);
    // Native REP chunk commits progress before a demand-page fault and retries.
    store64(ram+0x13020,0);store64(c+128,0x1000);store64(c+312,0);store64(c+8,64);store64(c+56,0x3ff0);
    expect(x86_run(c,run,200)==5 && !load64(c+8) && load64(c+56)==0x4030);
    expect(load8(ram+0x3ff0)==0x7f && load8(ram+0x3fff)==0x7f && load8(ram+0x30000)==0x7f && load8(ram+0x3002f)==0x7f);
    // Guest PTE writes and CR3 changes invalidate cached read translations.
    let patch="8b0c250040000048c7042520300100030004008b1c2500400000f4";j=0;while j<27 {store8(ram+0x1000+j,digit(load8(patch+j*2))*16+digit(load8(patch+j*2+1)));j=j+1;}
    store64(ram+0x13020,0x30003);store64(ram+0x30000,0xaa);store64(ram+0x40000,0xbb);store64(c+128,0x1000);store64(c+312,0);
    expect(x86_run(c,run,100)==5 && load64(c+8)==0xaa && load64(c+24)==0xbb);
    store64(ram+0x20000,0x21003);store64(ram+0x21000,0x22003);store64(ram+0x22000,0x23003);store64(ram+0x23008,0x1003);store64(ram+0x23020,0x40003);
    patch="8b0c250040000048b800000200000000000f22d88b1c2500400000f4";j=0;while j<28 {store8(ram+0x1000+j,digit(load8(patch+j*2))*16+digit(load8(patch+j*2+1)));j=j+1;}
    store64(ram+0x13020,0x30003);store64(c+128,0x1000);store64(c+312,0);
    expect(x86_run(c,run,100)==5 && load64(c+8)==0xaa && load64(c+24)==0xbb && load64(c+160)==0x20000);
    // Restart removes exception state and CR2 as well as general registers.
    reset(c,ram,"f4",1);expect(!load64(c+320) && !load64(c+328) && !load64(c+368));
    softvm_close(v);
    // Exercise the actual KVM setup path via the emulated API, including cleanup.
    kvm_emulated_api=1;let calls=kvme_calls;v=kvm_create(1048576);expect(v!=0 && kvme_calls>calls+8);
    expect(kvm_ioctl(load64(v+16),0xdead,0)<0);store8(load64(v+24)+0x1000,0xf4);expect(kvm_start(v,0x1000,16,0,0));expect(kvm_run(v)==5);kvm_close(v);
    expect(!kvme_cpu && !kvme_vm && !kvme_system);v=kvm_create(1048576);expect(v!=0);kvm_close(v);
    // Failure at each creation stage must release all partially owned resources.
    let requests=alloc(64);store64(requests,0xae01);store64(requests+8,0xae47);store64(requests+16,0x4020ae46);store64(requests+24,0xae41);
    store64(requests+32,0xae04);store64(requests+40,0xc008ae05);store64(requests+48,0x4008ae90);store64(requests+56,0xae00);
    let i=0;while i<8 {kvme_fail_request=load64(requests+i*8);expect(!kvm_create(1048576) && kvm_error==-5);expect(!kvme_cpu && !kvme_vm && !kvme_system);i=i+1;}
    v=kvm_create(1048576);expect(v!=0);
    store64(requests,0x8138ae83);store64(requests+8,0x4138ae84);store64(requests+16,0x4090ae82);
    i=0;while i<3 {kvme_fail_request=load64(requests+i*8);expect(!kvm_start(v,0x1000,16,0,0) && kvm_error==-5);i=i+1;}
    expect(kvm_start(v,0x1000,16,0,0));kvme_fail_request=0xae80;expect(kvm_run(v)==-1 && kvm_error==-5);
    kvm_close(v);expect(!kvme_cpu && !kvme_vm && !kvme_system);syscall(11,requests,64,0,0,0,0);kvm_emulated_api=0;
    return 0;
}
