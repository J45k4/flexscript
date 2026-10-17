import "../../emulator/x86/cpu.flex";
global checks=0;
fn expect(v) {checks=checks+1;if !v {let p=alloc(32);let at=31;store8(p+at,10);let value=checks;while value {at=at-1;store8(p+at,48+value%10);value=value/10;}syscall(1,2,"x87 assertion failed at check ",30,0,0,0);syscall(1,2,p+at,32-at,0,0,0);syscall(60,1,0,0,0,0,0);}return 0;}
fn reset(c,ram,text) {expect(x86_start(c,0x1000,32,0,0));store64(c+144,64);xf_hex(ram+0x1000,text);return 0;}
fn main(argc,argv) {
    expect(argc==2 || argc==3);x86_jit_enabled=argc==3;x86_jit_min_fuel=0;x86_jit_threshold=1;
    let ram=alloc(2097152);let c=x86_create(ram,2097152);let run=alloc(4096);let row=alloc(64);let fd=syscall(2,load64(argv+8),0,0,0,0,0);expect(fd>=0);let cases=0;
    while cases<2400 {
        expect(syscall(0,fd,row,64,0,0,0)==64);let op=load64(row);
        reset(c,ram,"dbe3d92c2500200000dd042510200000dd042508200000d8c1dd1c2518200000dd3c2520200000f4");
        let opcode=0xd8;let m=0xc1;if op==1 {m=0xc9;}else if op==2 {m=0xe1;}else if op==3 {m=0xf1;}else if op==4 {opcode=0xdb;m=0xf1;}else if op==5 {opcode=0xdb;m=0xe9;}
        store8(ram+0x1017,opcode);store8(ram+0x1018,m);
        xf_put16(ram+0x2000,load64(row+24));store64(ram+0x2008,load64(row+8));store64(ram+0x2010,load64(row+16));
        expect(x86_run(c,run,100)==5);
        if load64(ram+0x2018)!=load64(row+32) || (xf_u16(ram+0x2020)&0x387f)!=(load64(row+40)&0x387f) || (op>=4 && (load64(c+136)&0x8d5)!=load64(row+48)) {
            syscall(1,2,row,64,0,0,0);syscall(1,2,ram+0x2018,16,0,0,0);expect(0);
        }
        expect(load8(c+1028)==128 && xf_u16(c+1024)==load64(row+24));cases=cases+1;
    }
    expect(syscall(0,fd,row,64,0,0,0)==0);syscall(3,fd,0,0,0,0,0);
    // Integer conversions and extended (80-bit) register stack round-trip.
    reset(c,ram,"dbe3df2c2500200000db3c2510200000db2c2510200000df3c2520200000f4");store64(ram+0x2000,-123456789012345);
    expect(x86_run(c,run,100)==5 && load64(ram+0x2020)==-123456789012345);
    // Legacy save resets the FPU; restore recovers the register and control state.
    reset(c,ram,"dbe3d9e8dd342500300000dd242500300000dd1c2500200000f4");expect(x86_run(c,run,100)==5 && load64(ram+0x2000)==0x3ff0000000000000);
    expect(xf_u16(ram+0x3000)==0x37f && xf_u16(c+1024)==0x37f);
    // 14/94-byte operand-size override environment/save forms.
    reset(c,ram,"dbe3d9e866dd34250030000066dd242500300000dd1c2500200000f4");expect(x86_run(c,run,100)==5 && load64(ram+0x2000)==0x3ff0000000000000);
    // Nonwaiting status/control, exception clear and FNINIT initialization.
    reset(c,ram,"dbe3d9eed9e8d8f1dfe0dbe2dd3c2500200000dbe3d93c2510200000f4");expect(x86_run(c,run,100)==5 && (load64(c)&4) && !(xf_u16(ram+0x2000)&0x7f) && xf_u16(ram+0x2010)==0x37f);
    // A faulting output cannot pop the x87 stack or modify any output byte.
    reset(c,ram,"dbe3d9e8dd1c25fcff1f00f4");store64(ram+0x1ffff8,0x1122334455667788);
    expect(x86_run(c,run,100)==-1 && load64(ram+0x1ffff8)==0x1122334455667788 && load8(c+1028)==128);
    // Unmasked arithmetic and reserved instructions fail before native execution.
    reset(c,ram,"dbe3d92c2500200000d9e8f4");xf_put16(ram+0x2000,0x37e);expect(x86_run(c,run,100)==-1 && load8(c+1028)==0);
    reset(c,ram,"d9d1f4");expect(x86_run(c,run,100)==-1);
    reset(c,ram,"dbe3f4");store64(c+152,load64(c+152)|8);expect(x86_run(c,run,100)==-1 && load64(c+392)==263);
    // FXSAVE64/FXRSTOR64 preserves stack, XMM backing state and guest pointers.
    reset(c,ram,"dbe3d9e8480fae042500300000dbe3480fae0c2500300000dd1c2500200000f4");
    store64(c+1184,0x123456789abcdef0);store64(ram+0x31d0,0xfeedfacecafebeef);
    expect(x86_run(c,run,100)==5 && load64(ram+0x2000)==0x3ff0000000000000 && load64(c+1184)==0x123456789abcdef0);
    expect(load64(ram+0x31d0)==0xfeedfacecafebeef && load64(ram+0x3008)==0x1002 && (load64(ram+0x3018)>>32)==xf_mxcsr_mask());
    // MXCSR load/store and rejected reserved bits retain the prior state.
    reset(c,ram,"0fae1425002000000fae1c2510200000f4");store64(ram+0x2000,0x3f80);expect(x86_run(c,run,100)==5 && (load64(ram+0x2010)&0xffffffff)==0x3f80);
    reset(c,ram,"0fae142500200000f4");store64(ram+0x2000,0x10000);expect(x86_run(c,run,100)==-1 && (load64(c+1048)&0xffffffff)==0x1f80);
    reset(c,ram,"480fae042501300000f4");expect(x86_run(c,run,100)==-1 && load64(c+392)==2);
    // Independent vCPUs retain different register stacks across interleaving.
    let other=x86_create(ram,2097152);reset(c,ram,"dbe3d9ebf4");expect(x86_run(c,run,100)==5);
    reset(other,ram,"dbe3d9e8f4");expect(x86_run(other,run,100)==5);
    xf_hex(ram+0x1000,"dd1c2500200000f4");store64(c+128,0x1000);store64(other+128,0x1000);
    expect(x86_run(c,run,100)==5 && load64(ram+0x2000)==0x400921fb54442d18);expect(x86_run(other,run,100)==5 && load64(ram+0x2000)==0x3ff0000000000000);x86_close(other);
    // The host control word and XMM state survive every guest arithmetic call.
    let helper=alloc(4096);let host=alloc(1024);xf_hex(helper,"480fae07c3");xf_hex(helper+16,"d92fc3");xf_hex(helper+32,"f30f6f3fc3");xf_hex(helper+48,"480fae0fc3");expect(syscall(10,helper,4096,5,0,0,0)==0);
    ffi_call(helper,host,0,0,0,0,0);xf_put16(row,0x77f);ffi_call(helper+16,row,0,0,0,0,0);store64(row,0x123456789abcdef0);store64(row+8,0xfedcba9876543210);ffi_call(helper+32,row,0,0,0,0,0);
    reset(c,ram,"dbe3d9e8d9e8dec1f4");expect(x86_run(c,run,100)==5);ffi_call(helper,host+512,0,0,0,0,0);
    expect(xf_u16(host+512)==0x77f && load64(host+512+272)==0x123456789abcdef0 && load64(host+512+280)==0xfedcba9876543210);ffi_call(helper+48,host,0,0,0,0,0);
    syscall(11,host,1024,0,0,0,0);syscall(11,helper,4096,0,0,0,0);x86_close(c);syscall(11,ram,2097152,0,0,0,0);syscall(11,run,4096,0,0,0,0);syscall(11,row,64,0,0,0,0);return 0;
}
