import "../../emulator/x86/cpu.flex";
fn expect(v) {if !v {syscall(1,2,"SSE assertion failed\n",21,0,0,0);syscall(60,1,0,0,0,0,0);}return 0;}
fn reset(c) {expect(x86_start(c,0x1000,32,0,0));store64(c+144,64);store64(c+168,512);return 0;}
fn main(argc,argv) {
    expect(argc==2 || argc==3);x86_jit_enabled=argc==3;x86_jit_min_fuel=0;x86_jit_threshold=1;
    let ram=alloc(1048576);let c=x86_create(ram,1048576);let run=alloc(4096);let row=alloc(80);let fd=syscall(2,load64(argv+8),0,0,0,0,0);expect(fd>=0);let cases=0;
    while cases<4096 {
        expect(syscall(0,fd,row,80,0,0,0)==80);reset(c);let p=ram+0x1000;
        let at=xf_hex(p,"0fae142540200000f3440f6f0c2500200000f3440f6f342510200000");let op=load64(row);let prefix=0x66;let second=0xef;let immediate=-1;
        if op==1 {second=0xd4;}else if op==2 {second=0xfe;}else if op==3 {second=0xf8;}else if op==4 {second=0xd5;}else if op==5 {second=0x63;}else if op==6 {second=0xd1;}else if op==7 {second=0x70;immediate=0x1b;}else if op==8 {second=0x73;immediate=3;}
        else if op>=9 && op<=12 {second=0x58;if op==9 {prefix=0;}if op==11 {prefix=0xf3;}if op==12 {prefix=0xf2;}}
        else if op==13 {prefix=0;second=0x59;}else if op==14 {second=0x5e;}else if op==15 {second=0xc2;immediate=3;}
        if prefix {store8(p+at,prefix);at=at+1;}let rex=0x45;let modrm=0xce;if op==8 {rex=0x41;modrm=0xf9;}
        store8(p+at,rex);store8(p+at+1,0x0f);store8(p+at+2,second);store8(p+at+3,modrm);at=at+4;
        if immediate>=0 {store8(p+at,immediate);at=at+1;}xf_hex(p+at,"f3440f7f0c25202000000fae1c2548200000f4");
        store64(ram+0x2000,load64(row+8));store64(ram+0x2008,load64(row+16));store64(ram+0x2010,load64(row+24));store64(ram+0x2018,load64(row+32));store64(ram+0x2040,load64(row+40));
        expect(x86_run(c,run,100)==5);
        if load64(ram+0x2020)!=load64(row+48) || load64(ram+0x2028)!=load64(row+56) || (load64(ram+0x2048)&0xffffffff)!=load64(row+64) {syscall(1,2,row,80,0,0,0);expect(0);}
        expect(!load64(c+1184) && !load64(c+1184+15*16));cases=cases+1;
    }
    // Compare integer/vector transfers and mask extraction to native x86.
    while cases<4168 {
        expect(syscall(0,fd,row,80,0,0,0)==80);reset(c);let op=load64(row)-16;
        store64(c+80,load64(row+8));store64(c+1184+9*16,load64(row+8));store64(c+1192+9*16,load64(row+16));store64(c+1184+14*16,load64(row+24));store64(c+1192+14*16,load64(row+32));
        let code="66450f6ecaf4";
        if op==1 {code="664d0f6ecaf4";}else if op==2 {code="66450f7ef2f4";}else if op==3 {code="664d0f7ef2f4";}else if op==4 {code="f3450f7ecef4";}else if op==5 {code="66450fd6f1f4";}else if op==6 {code="66450fd7d6f4";}else if op==7 {code="450f50d6f4";}else if op==8 {code="66450f50d6f4";}
        xf_hex(ram+0x1000,code);expect(x86_run(c,run,100)==5 && load64(c+1184+9*16)==load64(row+48) && load64(c+1192+9*16)==load64(row+56) && load64(c+80)==load64(row+64));cases=cases+1;
    }
    // Native scalar signed integer conversions, all MXCSR rounding modes,
    // extended registers and both register and exact-width memory sources.
    while cases<4296 {
        expect(syscall(0,fd,row,80,0,0,0)==80);let op=load64(row)-32;let form=0;
        while form<2 {
            reset(c);store64(c+1048,load64(row+40)|(xf_mxcsr_mask()<<32));store64(c+80,load64(row+8));store64(c+1184+9*16,0x1122334455667788);store64(c+1192+9*16,0x8877665544332211);
            let width=4;if op&1 {width=8;}store64(ram+1048568,load64(row+8));if width==4 {let byte=0;while byte<4 {store8(ram+1048572+byte,load64(row+8)>>(byte*8));byte=byte+1;}}let p=ram+0x1000;let prefix=0xf3;if op>=2 {prefix=0xf2;}store8(p,prefix);let rex=0x45;if width==8 {rex=rex|8;}if form {rex=rex&~1;}store8(p+1,rex);store8(p+2,0x0f);store8(p+3,0x2a);
            if !form {xf_hex(p+4,"caf4");}else {if width==8 {xf_hex(p+4,"0c25f8ff0f00f4");}else {xf_hex(p+4,"0c25fcff0f00f4");}}
            expect(x86_run(c,run,100)==5 && load64(c+1184+9*16)==load64(row+48) && load64(c+1192+9*16)==load64(row+56) && (load64(c+1048)&0xffffffff)==load64(row+64));form=form+1;
        }cases=cases+1;
    }
    reset(c);store64(c+1184,99);store64(c+1192,100);xf_hex(ram+0x1000,"f2480f2a0425fcff0f00f4");expect(x86_run(c,run,100)==-1 && load64(c+1184)==99 && load64(c+1192)==100);
    while cases<4552 {
        expect(syscall(0,fd,row,80,0,0,0)==80);let op=load64(row)-40;let form=0;
        while form<2 {
            reset(c);store64(c+136,0xad7);store64(c+1184+9*16,load64(row+8));store64(c+1192+9*16,load64(row+16));store64(c+1184+14*16,load64(row+24));store64(c+1192+14*16,load64(row+32));store64(ram+1048568,load64(row+24));
            let p=ram+0x1000;let at=0;if op&1 {store8(p,0x66);at=1;}let rex=0x45;if form {rex=0x44;}store8(p+at,rex);store8(p+at+1,0x0f);store8(p+at+2,0x2e+(op>>1));at=at+3;
            if !form {xf_hex(p+at,"cef4");}else {xf_hex(p+at,"0c25f8ff0f00f4");}
            expect(x86_run(c,run,100)==5 && (load64(c+136)&0x8d5)==(load64(row+48)&0x8d5) && (load64(c+136)&~0x8d5)==(0xad7&~0x8d5) && (load64(c+1048)&0xffffffff)==load64(row+64) && load64(c+1184+9*16)==load64(row+8) && load64(c+1192+9*16)==load64(row+16));form=form+1;
        }cases=cases+1;
    }
    while cases<4936 {
        expect(syscall(0,fd,row,80,0,0,0)==80);let op=load64(row)-48;let form=0;
        while form<2 {
            reset(c);store64(c+1048,load64(row+40)|(xf_mxcsr_mask()<<32));store64(c+80,-1);store64(c+1184+14*16,load64(row+8));store64(c+1192+14*16,load64(row+16));store64(ram+1048568,load64(row+8));
            let p=ram+0x1000;let prefix=0xf3;if op&2 {prefix=0xf2;}store8(p,prefix);let rex=0x45;if op&1 {rex=rex|8;}if form {rex=rex&~1;}store8(p+1,rex);store8(p+2,0x0f);store8(p+3,0x2c+(op>>2));
            if !form {xf_hex(p+4,"d6f4");}else {xf_hex(p+4,"1425f8ff0f00f4");}
            expect(x86_run(c,run,100)==5 && load64(c+80)==load64(row+48) && (load64(c+1048)&0xffffffff)==load64(row+64) && load64(c+1184+14*16)==load64(row+8) && load64(c+1192+14*16)==load64(row+16));form=form+1;
        }cases=cases+1;
    }
    while cases<5416 {
        expect(syscall(0,fd,row,80,0,0,0)==80);let op=load64(row)-56;let form=0;
        while form<2 {
            reset(c);store64(c+1048,load64(row+40)|(xf_mxcsr_mask()<<32));store64(c+1184+9*16,load64(row+8));store64(c+1192+9*16,load64(row+16));store64(c+1184+14*16,load64(row+24));store64(c+1192+14*16,load64(row+32));
            let prefix=0;let second=0x5a;let width=8;if op==1 {prefix=0x66;width=16;}else if op==2 {prefix=0xf3;width=4;}else if op==3 {prefix=0xf2;}else if op>=4 && op<=6 {second=0x5b;width=16;if op==5 {prefix=0x66;}if op==6 {prefix=0xf3;}}else if op>=7 {second=0xe6;prefix=0xf3;if op==8 {prefix=0xf2;width=16;}if op==9 {prefix=0x66;width=16;}}
            let address=1048576-width;let i=0;while i<width {store8(ram+address+i,load8(row+24+i));i=i+1;}
            let p=ram+0x1000;let at=0;if prefix {store8(p,prefix);at=1;}let rex=0x45;if form {rex=0x44;}store8(p+at,rex);store8(p+at+1,0x0f);store8(p+at+2,second);at=at+3;
            if !form {xf_hex(p+at,"cef4");}else {store8(p+at,0x0c);store8(p+at+1,0x25);i=0;while i<4 {store8(p+at+2+i,address>>(i*8));i=i+1;}store8(p+at+6,0xf4);}
            expect(x86_run(c,run,100)==5 && load64(c+1184+9*16)==load64(row+48) && load64(c+1192+9*16)==load64(row+56) && (load64(c+1048)&0xffffffff)==load64(row+64));form=form+1;
        }cases=cases+1;
    }
    // Scalar memory loads/stores touch only their defined width.
    reset(c);store64(c+80,0xfedcba9876543210);store64(c+88,-1);store64(c+96,-1);
    xf_hex(ram+0x1000,"664d0f6eca664d0f7ecb66450f6ef266450f7ef4f3450f7ef966450fd6f8f4");
    expect(x86_run(c,run,100)==5 && load64(c+88)==0xfedcba9876543210 && load64(c+96)==0x76543210);
    expect(load64(c+1184+9*16)==0xfedcba9876543210 && !load64(c+1192+9*16));
    expect(load64(c+1184+14*16)==0x76543210 && !load64(c+1192+14*16));
    expect(load64(c+1184+15*16)==0xfedcba9876543210 && !load64(c+1192+15*16));
    expect(load64(c+1184+8*16)==0xfedcba9876543210 && !load64(c+1192+8*16));
    reset(c);store64(c+1184+14*16,0x800000007fffffff);store64(c+1192+14*16,0xffff000080000000);
    xf_hex(ram+0x1000,"66450fd7d6450f50de66450f50e6f4");
    expect(x86_run(c,run,100)==5 && load64(c+80)==0xc887 && load64(c+88)==14 && load64(c+96)==3);
    reset(c);store64(ram+1048568,0x1122334455667788);store64(c+1192,-1);
    xf_hex(ram+0x1000,"f30f7e0425f8ff0f00660fd6042500200000f4");
    expect(x86_run(c,run,100)==5 && load64(c+1184)==0x1122334455667788 && !load64(c+1192) && load64(ram+0x2000)==0x1122334455667788);
    reset(c);store64(c+1184,99);store64(c+1192,100);xf_hex(ram+0x1000,"f30f7e0425fcff0f00f4");
    expect(x86_run(c,run,100)==-1 && load64(c+1184)==99 && load64(c+1192)==100);
    reset(c);store64(c+1184,11);store64(c+1192,12);store64(c+1200,21);store64(c+1208,22);
    xf_hex(ram+0x1000,"0f16c10f13c0f4");expect(x86_run(c,run,100)==-1 && load64(c+392)==262 && load64(c+1184)==11 && load64(c+1192)==21);
    reset(c);store64(c+1184,11);store64(c+1192,12);store64(c+1200,21);store64(c+1208,22);
    xf_hex(ram+0x1000,"0f12c1f4");expect(x86_run(c,run,100)==5 && load64(c+1184)==22 && load64(c+1192)==12);
    reset(c);store64(ram+1048568,77);store64(c+1184,11);store64(c+1192,12);
    xf_hex(ram+0x1000,"660f160425f8ff0f00660f17042500200000f4");expect(x86_run(c,run,100)==5 && load64(c+1184)==11 && load64(c+1192)==77 && load64(ram+0x2000)==77);
    reset(c);xf_hex(ram+0x1000,"f30f100425feff0f00f30f11042500200000f4");store8(ram+0x2004,0x77);expect(x86_run(c,run,100)==-1 && !load64(c+1184));
    reset(c);xf_hex(ram+0x1000,"f20f10042500200000f20f11042510200000f4");store64(ram+0x2000,0x3ff0000000000000);store64(ram+0x2018,-1);expect(x86_run(c,run,100)==5 && load64(ram+0x2010)==0x3ff0000000000000 && load64(ram+0x2018)==-1);
    reset(c);xf_hex(ram+0x1000,"0f28042501200000f4");expect(x86_run(c,run,100)==-1 && load64(c+392)==2);
    reset(c);xf_hex(ram+0x1000,"0f58c1f4");store64(c+1048,0x1f00|(xf_mxcsr_mask()<<32));expect(x86_run(c,run,100)==-1 && !load64(c+1184));
    reset(c);xf_hex(ram+0x1000,"0f57c0f4");store64(c+168,0);expect(x86_run(c,run,100)==-1 && load64(c+392)==262);
    // Guest SIMD preserves the host MXCSR and unrelated host vector registers.
    let helper=alloc(4096);let host=alloc(1024);xf_hex(helper,"480fae07c3");xf_hex(helper+16,"0fae17c3");xf_hex(helper+32,"f3440f6f2fc3");xf_hex(helper+48,"480fae0fc3");expect(syscall(10,helper,4096,5,0,0,0)==0);
    ffi_call(helper,host,0,0,0,0,0);store64(row,0x5f80);ffi_call(helper+16,row,0,0,0,0,0);store64(row,0x123456789abcdef0);store64(row+8,0xfedcba9876543210);ffi_call(helper+32,row,0,0,0,0,0);
    reset(c);xf_hex(ram+0x1000,"0f57c00f58c1f4");expect(x86_run(c,run,100)==5);ffi_call(helper,host+512,0,0,0,0,0);
    expect((load64(host+512+24)&0xffffffff)==0x5f80 && load64(host+512+368)==0x123456789abcdef0 && load64(host+512+376)==0xfedcba9876543210);ffi_call(helper+48,host,0,0,0,0,0);
    syscall(11,host,1024,0,0,0,0);syscall(11,helper,4096,0,0,0,0);
    // Alternating instructions stay cached; eviction recompiles the correct
    // helper, and reset/another CPU cannot import stale vector or host state.
    let cached=x86_create(ram,1048576);reset(cached);store64(cached+1200,1);xf_hex(ram+0x1000,"660fefc1660fd4c1");let loop=0;
    while loop<100 {store64(cached+128,0x1000);expect(x86_step(cached,run)==0 && x86_step(cached,run)==0);loop=loop+1;}
    let cache=load64(cached+6936);expect(cache && load64(cache+8)==2 && load64(cached+1184)==200);
    let original=0x10066c1ef;let slot=((original*0x9e3779b185ebca87)>>57)&127;let collision=original+1;
    while (((collision*0x9e3779b185ebca87)>>57)&127)!=slot {collision=collision+1;}
    let entry=xf_helper(cached,collision);expect(entry && !load64(entry+16));xf_hex(load64(entry+8),"31c0c3");expect(xf_seal(cached,entry));
    store64(cached+1184,0);store64(cached+128,0x1000);expect(x86_step(cached,run)==0 && x86_step(cached,run)==0 && load64(cached+1184)==2 && load64(cache+8)==4);
    reset(cached);store64(cached+1200,1);expect(x86_step(cached,run)==0 && x86_step(cached,run)==0 && load64(cached+1184)==2 && load64(cache+8)==4);
    let other=x86_create(ram,1048576);reset(other);expect(x86_step(other,run)==0 && load64(other+6936)!=cache && load64(load64(other+6936)+8)==1 && !load64(other+1184) && load64(cached+1184)==2);
    xf_close(cached);expect(!load64(cached+6936));x86_close(cached);x86_close(other);
    syscall(3,fd,0,0,0,0,0);x86_close(c);syscall(11,ram,1048576,0,0,0,0);syscall(11,run,4096,0,0,0,0);syscall(11,row,80,0,0,0,0);return 0;
}
